# Testing `looped`

Two layers: **automated unit tests** for the pure services (fast, run them often),
and a **manual QA checklist** for the things that need a real audio file, the audio
engine, and your ears/eyes (looping seamlessness, waveform smoothness, gestures).

## Unit tests (automated)

The `loopedTests` target holds XCTest unit tests for the pure, dependency-free
services — `WaveformService` (windowing math), `LoopingService` (loop slice +
crossfade DSP), and `AudioFileService`'s duration-limit logic. They construct
their own in-memory buffers / tiny temp files, so no fixtures are needed.

Run from the repo root (the folder with `looped.xcodeproj`):

```bash
# CLI (Command Line Tools alone are not enough — point at the full Xcode):
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project looped.xcodeproj -scheme looped -destination 'platform=macOS'
```

In Xcode: **⌘U**, or click the diamond next to a test/class.

Files (`tests/Services/`):

| File | Covers |
|---|---|
| `WaveformServiceTests` | window width/offset/playheadX, bucket alignment, silence padding, sample copy, playhead clamp, `chunkX` inverse. |
| `LoopingServiceTests` | slice length, seam continuity (`out[0] == source[end]`), untouched tail, no-fade at song end, invalid-range → `nil`, out-of-bounds clamping. |
| `AudioFileServiceTests` | 20-minute limit boundary (pure `exceedsDurationLimit`), error messages, happy-path decode of a generated WAV. |

The audio engine (`PlaybackService`) and the view-models are **not** unit-tested —
they own the `AVAudioEngine` graph / `@Published` UI state and are best covered by
the manual pass below.

## Manual QA checklist

Do this after any change to playback, looping, the waveform, or the layout. Use a
real track (WAV/MP3/AIFF) a couple of minutes long.

**Load**
- [ ] Header **Load** (and the sidebar Open File button) opens the picker; a
      WAV/MP3/AIFF loads, name + `currentTime / fileTime` show, waveform renders.
- [ ] Loading a **> 20 min** file shows the "longer than 20 minutes" error, not a crash.

**Transport**
- [ ] Play/pause toggles (button **and** spacebar); the playhead advances.
- [ ] **Pause holds the playhead** where it stopped (no jump/reset); resume continues.
- [ ] Seeking while paused works and stays put.
- [ ] Stop returns to 0 and clears the playing state.
- [ ] Clicking any control does **not** freeze the waveform (timer runs in `.common`).

**Looping (A/B)**
- [ ] Set A, then B (B > A): playback loops the region.
- [ ] The loop is **seamless** — no click and no pitch/warble at the wrap.
- [ ] A/B markers + shaded region sit at the right spots and pan with the waveform.
- [ ] Scrubbing while looping stays in the loop (doesn't silently exit it).

**Waveform + scrubbing**
- [ ] Waveform pans smoothly under the fixed center iterator; peaks stay stable
      (no jitter/dancing). Note any flicker during playback (known open issue).
- [ ] Scrub (trackpad/drag) moves the timeline; release **snaps back** to the live
      playhead with an ease-out, or seeks if released in bounds.
- [ ] Out-of-bounds scrub keeps playing and eases back rather than crashing.

**Speed / volume**
- [ ] Speed slider changes tempo without altering pitch; volume slider works.

**Layout**
- [ ] Sidebar toggle animates and pushes content right; title + transport stay centered.
- [ ] Resizing the window re-lays out without re-analyzing/stuttering.

**Reload**
- [ ] Loading a second file resets loop points, time, and the waveform cleanly.
