# CLAUDE.md — `looped`

## Overview

`looped` is a **macOS SwiftUI** audio-looping app. It loads an audio file (WAV / MP3 / AIFF),
renders an interactive waveform, and plays it back with adjustable speed and volume, timeline
scrubbing via trackpad/mouse, and spacebar play/pause. It supports **A/B loop points**: setting
both arms a seamless loop by slicing the [A, B) region out of the loaded buffer and scheduling it
with `AVAudioPlayerNode`'s `.loops` option (see `activateLoop()`/`deactivateLoop()` in
`AudioEngineController`). The sliced buffer's seam is crossfaded (`crossfadeSeam`) so the loop wrap
stays sample-continuous — otherwise the `AVAudioUnitTimePitch` unit warps the pitch at the hard
cut, especially off 1× speed. A manual seek exits loop mode.

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
  into a single `AVAudioPCMBuffer` (`load(url:)`, `openFile()` — both `async`); `load(url:)`
  reconnects the graph at the file's `processingFormat` so the `.loops` buffer (raw, unconverted)
  plays at the correct pitch. Publishes
  `isPlaying`, `currentTime`, `duration`, `rate`, `timePitch`, `loopStart`/`loopEnd`
  (`(TimeInterval?, AVAudioFramePosition?)` tuples), `audioFile`, `currentFileName`, `rawSamples`,
  and `waveform` (currently an untyped `Any?` placeholder — not yet wired to the UI).
  Key methods: `togglePlayPause()`, `stop()`, `jumpTo(time:)` (reschedules a segment; exits loop
  mode), `updateRate()`, `updateVolume(volume:)`, `setLoopStart/End` (arm/disarm the loop via
  `refreshLoop`/`activateLoop`/`deactivateLoop`, backed by a sliced `.loops` buffer),
  `getProgressInPercent()`. Playback
  time is polled by a 0.03s `Timer` in `startUpdatingCurrentTime()`, installed in `.common`
  run-loop modes so the waveform keeps updating during AppKit event tracking (clicks/scrolls).
- **`OffsetCalculator`** (`Services/OffsetCalculator.swift`) — pure view-math for the waveform.
  Maps playback progress ↔ horizontal scroll offset so the waveform pans under a fixed center
  iterator; also computes loop-point x-positions. The waveform is rendered `zoom`× wider than the
  viewport (`contentWidth = waveformWidth * zoom`) so it pans faster; `waveformWidth` is the
  viewport width (used only for centering), `contentWidth` measures progress/loops/scrubbing.
  Publishes `isScrolling`, `currentScrollOffset`, `waveformWidth`, `zoom`.

## File map (10 Swift files)

| File | Role |
|---|---|
| `looped/loopedApp.swift` | `@main` App; wires up env objects, window sizing. |
| `looped/Views/ContentView.swift` | Main layout: header (Load/status) + waveform + controls; hosts `KeyboardHandler`. |
| `looped/Views/ControlsView.swift` | Play/pause/stop, speed slider (log ~0.5×–2×), volume slider, A/B loop buttons. |
| `looped/Views/WaveformView.swift` | Defines **`WaveformDisplayView`** + a private **`StripedWaveform`** (an `Equatable`, `.drawingGroup()`-cached single-color layer that runs its own `WaveformAnalyzer` — with a configurable `noiseFloorDecibelCutoff` to favor peaks — and renders a `WaveformShape`). Renders SoundCloud-style: a static upcoming (gray) layer + a played (orange) layer revealed by an animating mask — cached so the striped path isn't re-stroked every playhead tick — with A/B markers + shaded loop region; drives scroll via `ScrollObserverView`. |
| `looped/Views/Theme.swift` | Shared design tokens (`enum Theme`): warm-orange-on-black palette + waveform colors. Introduced for the waveform redesign; expanded by the UI redesign. |
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
- **Theming**: use color tokens from `enum Theme` (`looped/Views/Theme.swift`) rather than
  hardcoded `Color`/`NSColor` literals in views.

## Maintenance — keep this file current

After **any** change that affects architecture, the file map, build/run commands, dependencies,
or conventions, **update the relevant section of this file in the same change**. This is enforced
by a `Stop` hook in `.claude/settings.json`: if Swift sources are modified but `CLAUDE.md` is not,
the hook blocks the turn with a reminder. Doc-only or no-op turns are unaffected.
