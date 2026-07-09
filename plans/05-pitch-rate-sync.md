# 05 — Independent Rate + Pitch sliders, with sync (varispeed) toggle

**Depends on:** nothing (independent of the library work). Touches the clock — read
the notes; this is the trickiest plan.
**Scope:** replace the single "Pitch" (=rate) slider with Rate (tempo) + Pitch
(semitones) sliders and a sync toggle that makes one control behave like tape speed.

## Current state (anchors)

- Graph: `AVPlaybackService`: `player → timePitch (AVAudioUnitTimePitch) → mainMixer`.
- One slider ("Pitch", log-mapped 0.5×–2×) sets `PlayerViewModel.rate` →
  `PlaybackService.setRate` → `timePitch.rate`.
- The clock (`currentTime()`) counts **source frames** upstream of the effects and
  smooths against `now × rate` — any change to effective rate semantics must update
  `let rate = Double(timePitch.rate)` there (see notes).

## Technical notes (researched)

- `AVAudioUnitTimePitch.rate`: 1/32…32 (we keep 0.5–2). `.pitch`: **cents**,
  −2400…+2400 (we expose ±12 semitones = ±1200 cents). Both are live — no
  re-slicing of the loop buffer needed.
- **Sync mode quality:** driving `timePitch.rate` + a matching `.pitch =
  1200·log2(rate)` still runs the time-stretch *and* pitch-shift DSP (two artifact
  sources emulating what a resampler does natively). True tape-style varispeed is
  `AVAudioUnitVarispeed` — a plain resampler, artifact-free. Recommended graph:
  `player → timePitch → varispeed → mainMixer` (both attached once, neutral = rate 1 /
  pitch 0):
  - **Independent mode:** `timePitch.rate` = rate slider, `timePitch.pitch` = pitch
    slider; `varispeed.rate = 1`.
  - **Synced mode:** `varispeed.rate` = the one slider; timePitch neutral. Highest
    quality — this is the whole point of the toggle.
- **Clock impact (critical):** source frames are consumed at
  `timePitch.rate × varispeed.rate` per wall second. `currentTime()`'s smoothing
  must use that product as `rate`. (Verify with the scratchpad `ratetest.swift`
  harness pattern from the 2026-07-09 session: play silence, measure clock advance
  per wall second at varispeed 2×.)
- `setSource` reconnects the graph at the file's format — the new node must be
  reconnected there too.
- Switching modes mid-play: set the neutralized unit *first*, then the active one,
  to avoid a transient double-shift; a small click is acceptable, a sustained wrong
  pitch is not.
- UI state mapping when toggling sync: keep it simple — entering sync uses the rate
  slider's value as the varispeed value and disables the pitch slider (shown at the
  implied semitone value, `12·log2(rate)`); leaving sync restores independent values.

## Steps

1. `PlaybackService`: add `setPitch(cents:)` + `setVarispeed(rate:)` (or one
   `setPitchMode(...)` API — pick while implementing); attach + reconnect varispeed;
   fix the clock's rate product; extend `FakePlaybackService`.
2. Harness-verify the clock at varispeed ≠ 1 before UI work.
3. `PlayerViewModel`: `pitchSemitones`, `syncPitchAndRate` + intents.
4. `ControlsView`: second slider (Pitch in semitones, snap to integers, `%+d st`
   live label; Rate slider label `1.25×`), sync toggle between them.
5. Manual QA (TESTING.md): loop seam at extreme rate/pitch in both modes.
6. `CLAUDE.md` (graph, controls) + `plans/README.md`.

## Acceptance

- [ ] Rate slider changes tempo without pitch; Pitch slider transposes ±12 st
      without tempo change.
- [ ] Sync ON: one slider, tape-style (tempo+pitch together) via varispeed —
      audibly cleaner than independent mode at e.g. 0.6×.
- [ ] `currentTime` / waveform scroll / loop fold stay correct in both modes
      (harness-verified rate product).
- [ ] Live value labels per bug-fix #3 conventions.
