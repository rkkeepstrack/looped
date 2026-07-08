# Plan 2 — Fix A/B loop points (seamless looping)

> **Status (2026-07-07): implemented (Option A) + seam crossfade. Build-verified.**
> Removed the busy-wait `checkLoop()`; added
> `refreshLoop`/`activateLoop`/`deactivateLoop`/`makeLoopBuffer`, an explicit
> `isScheduled` flag, and loop-aware `getCurrentTime()`. Manual seek exits loop mode.
>
> **Follow-up 1 (seam):** added `crossfadeSeam` (equal-power blend of the audio
> following `end` into the loop head) so the `.loops` wrap is sample-continuous —
> avoids a click/warble through `AVAudioUnitTimePitch`.
>
> **Follow-up 2 (pitch drop — the real bug):** the loop played at the wrong pitch
> while normal playback was fine, and clearing the loop fixed it. Cause:
> `scheduleFile`/`Segment` sample-rate-convert, but `scheduleBuffer` (the loop
> path) plays raw at the node's output rate — and the graph was connected in
> `init` at the hardware rate, not the file's. Fixed by reconnecting the graph at
> `file.processingFormat` in `load(url:)`, so file and loop buffer share one rate.

**Type:** Functional bug (also a main-thread freeze)
**Depends on:** nothing. Can ship independently.
**Primary file:** `looped/Services/AudioEngineController.swift`

## Problem

When A and B loop points are set, playback should loop seamlessly between them,
jumping from B back to A. Today it doesn't loop — and worse, it can hang the app.

## Root cause

`checkLoop()` (`AudioEngineController.swift:222-236`) is called every 0.03 s from
the playback timer (`startUpdatingCurrentTime()`, line 144), and contains a
**busy-wait**:

```swift
isLooping = true
while isLooping {                                  // 236: spins forever on the main thread
    if (isPlaying && getCurrentSampleTime() == end) {
        jumpTo(time: start)
    }
}
```

Three defects:

1. **`while isLooping` never exits** — `isLooping` is only set to `false` at the
   top guard, which this loop never re-reaches. Because the timer fires on the
   main runloop, this **freezes the UI** the moment both points are set.
2. **Frame-domain mismatch** — `end` is `loopEnd.1`, a *file* frame position
   (`framePosition(for:)` = `time * sampleRate`, line 214-217), but
   `getCurrentSampleTime()` (line 164-167) returns `nodeTime.sampleTime`, the
   *render node's* running sample clock. They live in different timelines, so the
   `==` comparison is never meaningfully true.
3. **Exact `==` on a 0.03 s poll** — even in one timeline, sample-exact equality
   almost never lands on a tick boundary.

## Goal / desired behavior

- With A and B set (A < B), audio loops **seamlessly** (no audible gap/click) from
  B back to A, indefinitely, until loop is cleared or playback stopped.
- Setting only A, only B, or B ≤ A → no looping (defined, non-crashing behavior).
- Toggling loop on/off during playback works without restarting the track.
- No main-thread blocking.

## Approach

Two options; **recommend Option A** for true seamlessness.

### Option A (recommended) — schedule the loop region as a looping buffer

`AVAudioPlayerNode.scheduleBuffer(_:at:options:.loops)` loops a buffer at the
render layer, which is **sample-accurate and gap-free** (no polling).

- On "activate loop" (both points valid): build an `AVAudioPCMBuffer` containing
  only frames `[startFrame, endFrame)` sliced from `fullBuffer` (already loaded in
  `load(url:)`, line 86), then `player.stop()` and
  `scheduleBuffer(loopBuffer, at: nil, options: [.loops, .interrupts])`,
  `player.play()`.
- `currentTime` reporting must be mapped back into file time: while looping,
  `fileTime = loopStart + (renderElapsed % loopLength)`. Add a `loopStartTime`
  offset and modulo in `getCurrentTime()`.
- On "deactivate loop": `player.stop()`, reschedule the full file/segment from the
  current position (reuse `jumpTo`), resume if it was playing.

### Option B (simpler, not truly seamless) — corrected time-based poll

Keep the timer but replace the busy-wait with a single per-tick check in seconds:

```swift
if isLooping, let a = loopStart.0, let b = loopEnd.0, currentTime >= b {
    jumpTo(time: a)
}
```

Cheap, but `jumpTo` reschedules a segment → a small audible gap at each wrap, and
wrap accuracy is bounded by the 0.03 s tick. Acceptable as a stopgap.

## Step-by-step (Option A)

1. **Delete the busy-wait.** Replace `checkLoop()` body; remove the `while` loop.
   Remove the per-tick `print("LOOPS", …)` (line 223).
2. **Add loop state:** `private var loopBuffer: AVAudioPCMBuffer?`,
   `private var loopStartTime: TimeInterval = 0`, and treat `isLooping` as derived
   from "both points valid".
3. **`activateLoop()`**: validate `loopStart.1 < loopEnd.1`; slice `fullBuffer`
   into `loopBuffer` (copy channel data for the frame range); stop player,
   `scheduleBuffer(.loops)`, set `loopStartTime = loopStart.0`, play if needed.
4. **`deactivateLoop()`**: stop; `jumpTo(time: currentTime)` to restore normal
   full-file playback; resume if needed.
5. **Trigger points:** call `activateLoop()` from `setLoopStart/​setLoopEnd`
   (lines 206-212) once both are set and valid; call `deactivateLoop()` when
   either is cleared (the existing Reset button, `ControlsView.swift:58`).
6. **Fix `getCurrentTime()`** (line 157-162) to add `loopStartTime` and modulo the
   loop length while `isLooping`, so the timeline UI and waveform track correctly.
7. **Guard `jumpTo` / end-of-file**: `reachedEndOfFile()` (line 253) must not
   `stop()` while looping. Add `guard !isLooping` there or in the timer (line 146).
8. **Remove/retire** `AudioEngineBufferFunctions.swift` buffer helpers if unused
   after this (coordinate with Plan 4, which already flags it as dead code).

## Files touched

- `looped/Services/AudioEngineController.swift` (primary).
- `looped/Views/ControlsView.swift` — Reset button already calls
  `setLoopStart/End(nil)`; verify it now also deactivates the loop.
- `CLAUDE.md` — update the `checkLoop()` description ("naive busy-wait — do not
  treat as finished") to reflect the implemented approach.

## Risks & considerations

- **Buffer slicing correctness**: copy per-channel `floatChannelData` for the exact
  frame range; set `frameLength`. Off-by-one here = clicks. Unit-test the slice math.
- **Format/interleaving**: use `fullBuffer.format`; handle multi-channel.
- **Interaction with scrubbing**: scrubbing (`jumpTo` via scroll,
  `WaveformView.swift:85`) while a loop is active — decide whether scrubbing exits
  the loop or seeks within it. Recommend: scrubbing outside [A,B] deactivates loop.
- **Rate/pitch**: looping buffer still flows through `AVAudioUnitTimePitch`, so
  speed changes keep working; verify time-mapping under `rate != 1`.

## Acceptance criteria

- [~] Setting A then B starts a gap-free loop; audio wraps B→A indefinitely —
  *implemented* via `.loops` buffer; confirm by ear.
- [x] Clearing either point resumes normal playback from the current spot
  (`deactivateLoop` → `jumpTo(currentTime)`).
- [x] No UI freeze at any point (the busy-wait is removed).
- [~] Timeline text + waveform position stay correct inside the loop —
  *implemented* (`getCurrentTime` folds the render clock into `[A,B]`); confirm visually.
- [~] Works at non-1.0 playback rates — audio loops correctly (sample-accurate
  buffer); **caveat**: the displayed `currentTime` under rate ≠ 1 inherits the
  pre-existing `/rate` scaling in `getCurrentTime` (not introduced here).

## Open questions

- Should scrubbing inside the loop stay looped, or exit the loop?
- Do we want a visible on/off "loop active" toggle distinct from A/B being set?
