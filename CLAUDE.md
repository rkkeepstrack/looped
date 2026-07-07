# CLAUDE.md — `looped`

## Overview

`looped` is a **macOS SwiftUI** audio-looping app. It loads an audio file (WAV / MP3 / AIFF),
renders an interactive waveform, and plays it back with adjustable speed and volume, timeline
scrubbing via trackpad/mouse, and spacebar play/pause. An **A/B loop-point feature is in
progress** (see `checkLoop()` in `AudioEngineController`, currently a naive busy-wait — do not
treat it as finished).

- Platform: macOS only (deployment target **macOS 15.6**), universal (Intel + Apple Silicon).
- Frameworks: SwiftUI (UI), AppKit (scroll/keyboard capture), AVFoundation (audio), Combine.
- Single SPM dependency: **DSWaveformImage** v14.2.2 (`https://github.com/dmrschmidt/DSWaveformImage`).
- Tooling: **Xcode 26+** required (`LastUpgradeCheck = 2600`). Bundle id `RK.looped`.

## Directory layout (note the nesting)

- **Repo / git root** (this file, `.claude/`, `looped.xcodeproj`): `looped/looped/`
- **Source dir**: `looped/looped/looped/`

## Build & Run

Run from the repo root (the folder containing `looped.xcodeproj`):

```bash
xcodebuild -project looped.xcodeproj -scheme looped -configuration Debug build   # build
xcodebuild -project looped.xcodeproj -scheme looped clean                        # clean
xcodebuild -list                                                                 # list schemes/targets
```

Project, scheme, and target are all named `looped`. For normal development, build & run from
Xcode (⌘R) — it's a windowed macOS app (min size 1024×800, set in `loopedApp.swift`).

## Architecture (SwiftUI + MVVM)

`loopedApp.swift` (`@main`) creates two `@StateObject` `ObservableObject`s and injects them as
`environmentObject`s into `ContentView`:

- **`AudioEngineController`** (`Services/AudioEngineController.swift`) — the core. Owns the audio
  graph `AVAudioEngine → AVAudioPlayerNode → AVAudioUnitTimePitch → mainMixerNode`. Loads files
  into a single `AVAudioPCMBuffer` (`load(url:)`, `openFile()` — both `async`). Publishes
  `isPlaying`, `currentTime`, `duration`, `rate`, `timePitch`, `loopStart`/`loopEnd`
  (`(TimeInterval?, AVAudioFramePosition?)` tuples), `audioFile`, `currentFileName`, `rawSamples`,
  and `waveform` (currently an untyped `Any?` placeholder — not yet wired to the UI).
  Key methods: `togglePlayPause()`, `stop()`, `jumpTo(time:)` (reschedules a segment),
  `updateRate()`, `updateVolume(volume:)`, `setLoopStart/End`, `getProgressInPercent()`. Playback
  time is polled by a 0.03s `Timer` in `startUpdatingCurrentTime()`.
- **`OffsetCalculator`** (`Services/OffsetCalculator.swift`) — pure view-math for the waveform.
  Maps playback progress ↔ horizontal scroll offset so the waveform pans under a fixed center
  iterator; also computes loop-point x-positions. Publishes `isScrolling`, `currentScrollOffset`,
  `waveformWidth`.

## File map (9 Swift files)

| File | Role |
|---|---|
| `looped/loopedApp.swift` | `@main` App; wires up env objects, window sizing. |
| `looped/Views/ContentView.swift` | Main layout: header (Load/status) + waveform + controls; hosts `KeyboardHandler`. |
| `looped/Views/ControlsView.swift` | Play/pause/stop, speed slider (log ~0.5×–2×), volume slider, A/B loop buttons. |
| `looped/Views/WaveformView.swift` | Defines **`struct WaveformDisplayView`** — renders DSWaveformImage, drives scroll via `ScrollObserverView`. |
| `looped/Views/ScrollObserverView.swift` | `NSViewRepresentable` capturing scroll-wheel + mouse-drag → `OffsetCalculator`. |
| `looped/Services/AudioEngineController.swift` | Core audio engine & playback state (see Architecture). |
| `looped/Services/OffsetCalculator.swift` | Waveform pan / timeline offset math. |
| `looped/Services/AudioEngineBufferFunctions.swift` | **Legacy/alternative** buffer-based helpers; not the active playback path. |
| `looped/Utils/KeyboardHandler.swift` | `NSViewRepresentable` global key monitor; spacebar → play/pause. |

Tests: `tests/Views/ContentViewTests.swift` exists but is **empty** (no tests yet).

## Conventions

- SwiftUI-first; drop to AppKit (`NSViewRepresentable`) only for scroll and keyboard capture.
- State via `@Published` / `@EnvironmentObject` / `@StateObject` (Combine is `internal import`ed
  but mostly used indirectly through `ObservableObject`).
- `async/await` for file I/O (`openFile`, `load`, `loadDuration`).
- `// MARK:` section markers throughout controllers.
- **SwiftFormat** config at `looped/.swiftformat` — **tabs** for indentation, trailing commas
  always. Run SwiftFormat before committing if available.

## Maintenance — keep this file current

After **any** change that affects architecture, the file map, build/run commands, dependencies,
or conventions, **update the relevant section of this file in the same change**. This is enforced
by a `Stop` hook in `.claude/settings.json`: if Swift sources are modified but `CLAUDE.md` is not,
the hook blocks the turn with a reminder. Doc-only or no-op turns are unaffected.
