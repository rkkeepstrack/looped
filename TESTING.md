# Testing `looped`

Two layers: **automated unit tests** (fast, headless, run them often) and a **manual
QA checklist** for what needs a real audio file, the audio engine, and your ears/eyes
(loop seamlessness, waveform smoothness). Items already covered by an automated test
are tagged **[auto]** below — the manual pass is then just a sanity confirmation.

## Unit tests (automated)

Run headless — no Xcode, no app host, no audio device:

```bash
just test                     # → swift test
just test --filter Looping     # pass args straight through
```

The `loopedTests` SwiftPM target has two layers:

**Pure services** — dependency-free logic, in-memory buffers / tiny temp files:

| File | Covers |
|---|---|
| `WaveformServiceTests` | window width/offset/playheadX, bucket alignment, silence padding, sample copy, playhead clamp, `chunkX` inverse. |
| `LoopingServiceTests` | slice length, seam continuity (`out[0] == source[end]`), untouched tail, no-fade at song end, invalid-range → `nil`, out-of-bounds clamping. |
| `AudioFileServiceTests` | 20-minute limit boundary (pure `exceedsDurationLimit`), error messages, happy-path decode of a generated WAV. |

**View-models** — behavior via injected test doubles (`Support/TestDoubles.swift`):

| File | Covers |
|---|---|
| `PlayerViewModelTests` | load populates state / rejects > 20 min; play-pause; stop resets; `jumpTo` seeks in-bounds, ignores out-of-bounds, no-ops while looping; A/B arms/disarms the loop; rate/volume reach the player. |
| `WaveformViewModelTests` | scroll-offset → center-time shift; scrub end/immediate-snap state; window delegates to `WaveformService`. |

Not automated: the real **`AVPlaybackService`** engine graph (needs an audio device) and
anything perceptual (loop *sound*, waveform *smoothness*) — those are the manual pass.

## Manual QA checklist

Do this after any change to playback, looping, the waveform, or the layout. Use a
real track (WAV/MP3/AIFF) a couple of minutes long. Launch with `just run`.

**Load**
- [ ] Header **Load** (and the sidebar Open File button) opens the picker; a
      WAV/MP3/AIFF loads, name + `currentTime / fileTime` show, waveform renders.
- [ ] Loading a **> 20 min** file shows the "longer than 20 minutes" error, not a crash. **[auto]**

**Transport**
- [ ] Play/pause toggles (button **and** spacebar); the playhead advances. **[auto: state]**
- [ ] **Pause holds the playhead** where it stopped (no jump/reset); resume continues.
- [ ] Seeking while paused works and stays put.
- [ ] Stop returns to 0 and clears the playing state. **[auto]**
- [ ] Clicking any control does **not** freeze the waveform (timer runs in `.common`).

**Looping (A/B)**
- [ ] Set A, then B (B > A): playback loops the region. **[auto: arming]**
- [ ] The loop is **seamless** — no click and no pitch/warble at the wrap.
- [ ] A/B markers + shaded region sit at the right spots and pan with the waveform.
- [ ] Scrubbing while looping stays in the loop (doesn't silently exit it). **[auto]**

**Waveform + scrubbing**
- [ ] Waveform pans smoothly under the fixed center iterator; peaks stay stable
      (no jitter/dancing). Note any flicker during playback (known open issue).
- [ ] Scrub (trackpad/drag) moves the timeline; release **snaps back** to the live
      playhead with an ease-out, or seeks if released in bounds. **[auto: state]**
- [ ] Out-of-bounds scrub keeps playing and eases back rather than crashing. **[auto]**

**Speed / volume**
- [ ] Speed slider changes tempo without altering pitch; volume slider works. **[auto: wiring]**

**Layout**
- [ ] Sidebar toggle animates and pushes content right; title + transport stay centered.
- [ ] Resizing the window re-lays out without re-analyzing/stuttering.

**Reload**
- [ ] Loading a second file resets loop points, time, and the waveform cleanly. **[auto]**
