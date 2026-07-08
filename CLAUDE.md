# CLAUDE.md — `looped`

## Overview

`looped` is a **macOS SwiftUI** audio-looping app. It loads an audio file (WAV / MP3 / AIFF),
renders an interactive waveform, and plays it back with adjustable speed and volume, timeline
scrubbing via trackpad/mouse, and spacebar play/pause. It supports **A/B loop points**: setting
both arms a seamless loop by slicing the [A, B) region out of the loaded buffer and scheduling it
with `AVAudioPlayerNode`'s `.loops` option (`PlayerViewModel` arms it; `LoopingService` slices +
crossfades the seam so the wrap stays sample-continuous — otherwise `AVAudioUnitTimePitch` warps
the pitch at the hard cut, especially off 1× speed; `PlaybackService` schedules it). A manual seek
exits loop mode.

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

## Architecture (SwiftUI + MVVM, DI'd services)

Layered **View → ViewModel → Service** (+ a `Model`), with one-way dependencies.
`loopedApp.swift` (`@main`) is the **composition root**: it constructs the services, injects them
into `PlayerViewModel`, and injects both view-models into `ContentView` as `environmentObject`s.
There is no DI framework — plain constructor injection; services sit behind protocols so they can
be mocked.

**View-models** (`ObservableObject`, the SwiftUI-facing state; think Angular component class):

- **`PlayerViewModel`** (`ViewModels/PlayerViewModel.swift`) — the playback presentation layer.
  Holds the `@Published` state the views bind to (`isPlaying`, `currentTime`, `duration`, `rate`,
  `loopStart`/`loopEnd` `(TimeInterval?, AVAudioFramePosition?)` tuples, `currentFileName`,
  `audioURL`), owns the 0.03s refresh `Timer` (installed in `.common` run-loop modes so the
  waveform keeps updating during AppKit event tracking), and turns view intents
  (`openFile`, `togglePlayPause`, `stop`, `jumpTo`, `setLoopStart/End`, `updateRate/Volume`) into
  calls on the injected services. Owns no audio graph and no view layout.
- **`WaveformViewModel`** (`ViewModels/WaveformViewModel.swift`) — pure view-math for the waveform
  (was `OffsetCalculator`). Maps playback progress ↔ horizontal scroll offset so the waveform pans
  under a fixed center iterator; computes loop-point x-positions. The waveform is rendered `zoom`×
  wider than the viewport (`contentWidth = waveformWidth * zoom`) so it pans faster (`waveformWidth`
  = viewport width, for centering only). Publishes `isScrolling`, `currentScrollOffset`,
  `waveformWidth`, `zoom`.

**Services** (plain, protocol-backed, no SwiftUI):

- **`PlaybackService`** / `AVPlaybackService` (`Services/PlaybackService.swift`) — the audio
  "player": owns the graph `AVAudioEngine → AVAudioPlayerNode → AVAudioUnitTimePitch →
  mainMixerNode` and the transport (`play/pause/stop/seek`), loop scheduling
  (`scheduleLoop`/`clearLoop`, a sliced `.loops` buffer), and the playback clock (`currentTime()`,
  loop-aware). `setSource(file:format:)` reconnects the graph at the file's sample rate so the raw
  `.loops` buffer plays at the correct pitch.
- **`AudioFileService`** / `DefaultAudioFileService` (`Services/AudioFileService.swift`) — decodes
  a URL into a `LoadedAudio` (`async`, off-main); URL-based and UI-free (the open panel lives in
  the view-model), so drag-and-drop can reuse it later.
- **`LoopingService`** / `DefaultLoopingService` (`Services/LoopingService.swift`) — pure loop DSP:
  slices the [A, B) region out of a source buffer and crossfades the seam so the `.loops` wrap is
  sample-continuous (avoids a click / time-pitch warble). Produces the buffer; the view-model hands
  it to `PlaybackService` to schedule.

**Model:** `LoadedAudio` (`Models/LoadedAudio.swift`) — value type: url, file, buffer, format, duration.

## File map (14 Swift files)

| File | Role |
|---|---|
| `looped/loopedApp.swift` | `@main` App; composition root (build services → inject view-models); window sizing. |
| `looped/Models/LoadedAudio.swift` | Value type: decoded file + buffer + format + duration. |
| `looped/Services/PlaybackService.swift` | `PlaybackService` protocol + `AVPlaybackService`: audio graph, transport, loop scheduling, playback clock. |
| `looped/Services/AudioFileService.swift` | `AudioFileService` protocol + default: `async` URL → `LoadedAudio` decode. |
| `looped/Services/LoopingService.swift` | `LoopingService` protocol + default: pure loop-buffer slicing + seam crossfade. |
| `looped/ViewModels/PlayerViewModel.swift` | Playback state/intents/timer; drives the services (see Architecture). |
| `looped/ViewModels/WaveformViewModel.swift` | Waveform pan / zoom / loop-point offset math (was `OffsetCalculator`). |
| `looped/Views/ContentView.swift` | Main layout: header (Load/status) + waveform + controls; hosts `KeyboardHandler`. |
| `looped/Views/ControlsView.swift` | Play/pause/stop, speed slider (log ~0.5×–2×), volume slider, A/B loop buttons. |
| `looped/Views/WaveformView.swift` | **`WaveformDisplayView`** + private **`StripedWaveform`** (`Equatable`, `.drawingGroup()`-cached layer running its own `WaveformAnalyzer` w/ configurable `noiseFloorDecibelCutoff`, rendering a `WaveformShape`). SoundCloud-style upcoming/played layers + mask, A/B markers, shaded loop region; drives scroll via `ScrollObserverView`. |
| `looped/Views/Theme.swift` | Shared design tokens (`enum Theme`): warm-orange-on-black palette + waveform colors. |
| `looped/Views/ScrollObserverView.swift` | `NSViewRepresentable` capturing scroll-wheel + mouse-drag → `WaveformViewModel`. |
| `looped/Utils/KeyboardHandler.swift` | `NSViewRepresentable` global key monitor; spacebar → play/pause. |
| `looped/Utils/TimeFormatter.swift` | `enum TimeFormatter`: formats playback times as `m:ss`. |

Tests: `tests/Views/ContentViewTests.swift` exists but is **empty** (no tests yet).

## Conventions

- SwiftUI-first; drop to AppKit (`NSViewRepresentable`) only for scroll and keyboard capture.
- **Layering**: `View → ViewModel → Service` (folders `Models/`, `Services/`, `ViewModels/`,
  `Views/`, `Utils/`). Views hold no logic; view-models hold `@Published` state + intents; services
  are plain (no SwiftUI) and sit behind protocols. Keep audio/UI-agnostic code out of the views and
  presentation state out of the services.
- **Dependency injection**: constructor injection wired at the composition root (`loopedApp`); no
  DI framework. New services get a `protocol` + a `Default…`/`AV…` implementation.
- State via `@Published` / `@EnvironmentObject` / `@StateObject` (Combine is `internal import`ed
  but mostly used indirectly through `ObservableObject`).
- `async/await` for file I/O (`openFile`, `AudioFileService.load`).
- `// MARK:` section markers throughout.
- **SwiftFormat** config at `looped/.swiftformat` — **tabs** for indentation, trailing commas
  always. Run SwiftFormat before committing if available.
- **Theming**: use color tokens from `enum Theme` (`looped/Views/Theme.swift`) rather than
  hardcoded `Color`/`NSColor` literals in views.

## Maintenance — keep this file current

After **any** change that affects architecture, the file map, build/run commands, dependencies,
or conventions, **update the relevant section of this file in the same change**. This is enforced
by a `Stop` hook in `.claude/settings.json`: if Swift sources are modified but `CLAUDE.md` is not,
the hook blocks the turn with a reminder. Doc-only or no-op turns are unaffected.
