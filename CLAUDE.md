# CLAUDE.md — `looped`

## Overview

`looped` is a **macOS SwiftUI** audio-looping app. It loads an audio file (WAV / MP3 / AIFF),
renders an interactive waveform, and plays it back with adjustable speed and volume, timeline
scrubbing via trackpad/mouse, and spacebar play/pause. It supports **A/B loop points**: setting
both arms a seamless loop by slicing the [A, B) region out of the loaded buffer and scheduling it
with `AVAudioPlayerNode`'s `.loops` option (`PlayerViewModel` arms it; `LoopingService` slices +
crossfades the seam so the wrap stays sample-continuous — otherwise `AVAudioUnitTimePitch` warps
the pitch at the hard cut, especially off 1× speed; `PlaybackService` schedules it). While a loop
is armed, scrubbing stays in the loop rather than tearing it down; seeks are clamped to the file
bounds (scrubbing out of range can't crash the player).

- Platform: macOS only (deployment target **macOS 15**, `Package.swift`).
- Frameworks: SwiftUI (UI), AppKit (scroll/keyboard capture), AVFoundation (audio), Combine.
- Single dependency: **DSWaveformImage** v14.2.2 (`https://github.com/dmrschmidt/DSWaveformImage`).
- Build system: **Swift Package Manager** (no `.xcodeproj`). Language mode **5** (`swiftLanguageModes:
  [.v5]`) — the sources predate Swift 6 strict concurrency. Bundle id `RK.looped`.
- Tooling: `just` (command interface), `swift`/SwiftPM, `swiftformat`. Build, run, *and* test all work
  on just the **Command Line Tools** — no full Xcode. Tests use **Swift Testing** (a pinned source
  dependency), not XCTest, so `swift test` needs no Xcode-only frameworks. Edit in any editor (Zed etc.).

## Directory layout

Standard SwiftPM layout, everything under the repo/git root (this file, `Package.swift`, `.claude/`):

- **`Sources/looped/`** — app sources (module `looped`): `loopedApp.swift` + `Models/`, `Services/`,
  `ViewModels/`, `Views/`, `Utils/` (+ `Assets.xcassets`, excluded from the build).
- **`Tests/loopedTests/`** — unit tests (module `loopedTests`): `Services/`, `ViewModels/`,
  `Support/`, `Views/`.
- **`plans/`** — remaining-work docs (`README.md` first).

## Build & Run

Prerequisites: the **Command Line Tools** (`xcode-select --install`) and `brew bundle` (installs
`just` + `swiftformat`). No full Xcode needed — build, run, and test all work on the CLT. Everything
runs through **`just`** (see `justfile`); run `just` alone to list recipes. Quickstart lives in
`README.md`.

```bash
just build          # swift build (debug)
just run            # build a .app bundle (inlined in the justfile) and open it — proper GUI app
just test           # swift test — headless unit tests, no Xcode (pass args: just test --filter Looping)
just format         # swiftformat .   (just format-check to lint only)
just clean          # swift package clean + remove .build/Looped.app
```

`swift build`/`swift test` also work directly. `just run` assembles `.build/Looped.app` (an
`Info.plist` + the SwiftPM binary) and `open`s it so it launches as a real foreground app
(Dock/menu/focus) rather than a bare executable — it's a windowed app (min 1024×800, set in
`loopedApp.swift`).

## Architecture (SwiftUI + MVVM, DI'd services)

Layered **View → ViewModel → Service** (+ a `Model`), with one-way dependencies.
`loopedApp.swift` (`@main`) is the **composition root**: it constructs the services, injects them
into `PlayerViewModel`, and injects both view-models into `ContentView` as `environmentObject`s.
There is no DI framework — plain constructor injection; services sit behind protocols so they can
be mocked.

**View-models** (`ObservableObject`, the SwiftUI-facing state; think Angular component class):

- **`PlayerViewModel`** (`ViewModels/PlayerViewModel.swift`) — the playback presentation layer.
  Holds the `@Published` state the views bind to (`isPlaying`, `currentTime`, `duration`, `rate`, `pitchSemitones`, `syncPitchAndRate`,
  `loopStart`/`loopEnd` `(TimeInterval?, AVAudioFramePosition?)` tuples, `currentFileName`,
  `audioURL`), owns the 0.03s refresh `Timer` (installed in `.common` run-loop modes so the
  waveform keeps updating during AppKit event tracking), and turns view intents
  (`openFile`, `togglePlayPause`, `stop`, `jumpTo`, `setLoopStart/End`, `updateRate/Pitch/Sync/Volume`) into
  calls on the injected services. Also exposes `livePlaybackTime()`, an uncached read of the
  playback clock (no observer invalidation) for per-display-frame rendering — the waveform's
  `TimelineView` uses it instead of the timer-published `currentTime` (which feeds the labels).
  Owns no audio graph and no view layout.
- **`WaveformViewModel`** (`ViewModels/WaveformViewModel.swift`) — observable state + gestures for
  the waveform (was `OffsetCalculator`). Holds `@Published` `samples` / `waveformWidth` /
  `isScrolling` / `currentScrollOffset`, owns scrubbing + the snap-back animation
  (`animateSnapBack`, a manual per-frame decay). A scrub latches an anchor time
  (`onScrollChange(playbackTime:)`) so the viewport holds still in song coordinates while
  playback runs on (the played edge travels out of view); release rebases the offset onto the
  live playhead so the snap-back converges on playback. And it **delegates the windowing/analysis math to the
  injected `WaveformService`** (`window(playbackTime:)`, `prepare(url:duration:noiseFloor:)`).

**Services** (plain, protocol-backed, no SwiftUI):

- **`PlaybackService`** / `AVPlaybackService` (`Services/PlaybackService.swift`) — the audio
  "player": owns the graph `AVAudioEngine → AVAudioPlayerNode → AVAudioUnitTimePitch →
  AVAudioUnitVarispeed → mainMixerNode` (`setRate`/`setPitch` drive the time-pitch unit,
  `setVarispeed` the resampler; the inactive unit stays neutral) and the transport
  (`play/pause/stop/seek`), loop scheduling
  (`scheduleLoop`/`clearLoop`, a sliced `.loops` buffer), and the playback clock (`currentTime()`,
  loop-aware; projected onto the wall clock via the render timestamp's host time — the
  buffer's *presentation* time — and low-pass filtered, so it's continuous rather than
  quantized to the ~6–12ms render cycle. The player node's sample clock counts *source*
  frames — it sits upstream of both effect units — which are consumed at the
  `timePitch.rate × varispeed.rate` product; the wall-clock smoothing uses that product,
  no division back to source time). `setSource(file:format:)` reconnects the graph at the file's sample rate so the raw
  `.loops` buffer plays at the correct pitch.
- **`AudioFileService`** / `DefaultAudioFileService` (`Services/AudioFileService.swift`) — decodes
  a URL into a `LoadedAudio` (`async`, off-main); URL-based and UI-free (the open panel lives in
  the view-model), so drag-and-drop can reuse it later. Rejects tracks longer than
  `maxDurationMinutes` (20) with `AudioFileServiceError.tooLong` (surfaced as `PlayerViewModel.loadError`).
- **`LoopingService`** / `DefaultLoopingService` (`Services/LoopingService.swift`) — pure loop DSP:
  slices the [A, B) region out of a source buffer and crossfades the seam so the `.loops` wrap is
  sample-continuous (avoids a click / time-pitch warble). Produces the buffer; the view-model hands
  it to `PlaybackService` to schedule.
- **`WaveformService`** / `DefaultWaveformService` (`Services/WaveformService.swift`) — pure
  waveform computation: `analyze(url:…)` (whole-song amplitude envelope via `WaveformAnalyzer`,
  off-main) and `window(samples:layout:centerTime:playbackTime:)` (the bucket-aligned viewport
  slice + offset + played-edge). Types `WaveformLayout` (geometry inputs) and `WaveformWindow`
  (result). No SwiftUI/state → unit-testable.

**Model:** `LoadedAudio` (`Models/LoadedAudio.swift`) — value type: url, file, buffer, format, duration.

## File map (15 Swift files)

| File | Role |
|---|---|
| `Sources/looped/loopedApp.swift` | `@main` App; composition root (build services → inject view-models); window sizing, dark scheme, `Theme.background`. |
| `Sources/looped/Models/LoadedAudio.swift` | Value type: decoded file + buffer + format + duration. |
| `Sources/looped/Services/PlaybackService.swift` | `PlaybackService` protocol + `AVPlaybackService`: audio graph, transport, loop scheduling, playback clock. |
| `Sources/looped/Services/AudioFileService.swift` | `AudioFileService` protocol + default: `async` URL → `LoadedAudio` decode; rejects tracks > 20 min. |
| `Sources/looped/Services/LoopingService.swift` | `LoopingService` protocol + default: pure loop-buffer slicing + seam crossfade. |
| `Sources/looped/Services/WaveformService.swift` | `WaveformService` protocol + default: pure whole-song analysis + bucket-aligned window math (`WaveformLayout`/`WaveformWindow`). |
| `Sources/looped/ViewModels/PlayerViewModel.swift` | Playback state/intents/timer; drives the services (see Architecture). |
| `Sources/looped/ViewModels/WaveformViewModel.swift` | Waveform observable state + scrubbing/snap-back (was `OffsetCalculator`); delegates windowing/analysis to `WaveformService`. |
| `Sources/looped/Views/ContentView.swift` | Root layout: animated collapsible **`Sidebar`** (private; import button now, track list in the player-features plan) + a top-left toggle (`@AppStorage "sidebarOpen"`) + centered header (name + `currentTime | fileTime`) + waveform + bottom bar; hosts `KeyboardHandler`. |
| `Sources/looped/Views/ControlsView.swift` | The bottom bar: Volume + Rate (log ~0.5×–2×, labeled "Speed" when synced) + Pitch (±12 semitones) `CompactSlider`s and a "Sync pitch & rate" checkbox (varispeed mode: one slider = tempo+pitch together, pitch slider disabled showing the implied shift) bottom-left, play/pause + stop center, `LoopPanel` (A/B + Reset, `«`/`»` arrows nudge a set point ±0.05 s, disabled while unset; nudging re-arms via `PlayerViewModel.nudgeLoopStart/End(by:)`, clamped to the file bounds and a `minLoopGap` of 0.05 s) bottom-right; sliders show the formatted current value in place of their label while dragging; clicking a slider's label (shows "Reset" on hover) resets it to its default (100 % / 1.0× / 0 st). `CompactSlider`/`LoopPanel` are private. |
| `Sources/looped/Views/WaveformView.swift` | **`WaveformDisplayView`** — windowed render: two viewport-sized `SyncWaveformCanvas` layers (gray upcoming + orange played, masked to the playhead) fed the visible sample slice from `WaveformViewModel`, plus a light-blue scrub-highlight layer (`Theme.waveformScrub`, masked between the played edge and the scrub cursor while scrubbing), A/B markers + shaded loop region (`.position`) and the center iterator; drives scroll via `ScrollObserverView`; while playing, a `TimelineView(.animation)` re-evaluates the window per display frame (the 0.03s timer only feeds labels) via `PlayerViewModel.livePlaybackTime()`, so the pan tracks the display clock. `SyncWaveformCanvas` (private) is a `WaveformLiveCanvas` clone that draws **synchronously** (`Canvas(rendersAsynchronously: false)`, same `WaveformImageDrawer` call) so the per-tick reslice and its compensating `.offset` commit in one pass — the library's async canvas lagged a frame and made the seam flicker. |
| `Sources/looped/Views/Theme.swift` | Shared design tokens (`enum Theme`): warm-orange-on-black palette, waveform colors, and layout metrics (sidebar width, panel corner/border). |
| `Sources/looped/Views/ScrollObserverView.swift` | `NSViewRepresentable` capturing scroll-wheel + mouse-drag → `WaveformViewModel`. |
| `Sources/looped/Utils/KeyboardHandler.swift` | `NSViewRepresentable` global key monitor; spacebar → play/pause. |
| `Sources/looped/Utils/TimeFormatter.swift` | `enum TimeFormatter`: formats playback times as `m:ss`. |

**Build/tooling files:** `Package.swift` (SwiftPM manifest: exe target `looped` + test target
`loopedTests`, deps DSWaveformImage + `swift-testing` (pinned `.exact("6.1.3")`), `swiftLanguageModes:
[.v5]`), `justfile` (command interface;
the `bundle` recipe assembles the `.app` for `just run`, in Python via `plistlib`), `.swiftformat`
(repo-root config), `Brewfile` (`just` + `swiftformat`, via `brew bundle`), `README.md` (quickstart).

## Tests

The **`loopedTests`** SwiftPM test target (`@testable import looped`) uses **Swift Testing**
(`@Test`/`#expect`, not XCTest) and runs **headless** via `just test` / `swift test` — no Xcode, no
app host, no audio device (~0.03s once built). Swift Testing comes from the pinned `swift-testing`
source dependency (so the CLT, which lacks both XCTest and the toolchain's bundled Testing, suffice).
Gotchas: the first build compiles `swift-testing` + SwiftSyntax from source (slower, then cached);
**switching toolchains** (CLT ↔ Xcode) needs `just clean` first — the macro plugin cache is
toolchain-specific. Two layers:

_Pure services_ (dependency-free logic):
- `Tests/loopedTests/Services/WaveformServiceTests.swift` — window math (bucket alignment,
  offset/playhead, silence padding, `chunkX`).
- `Tests/loopedTests/Services/LoopingServiceTests.swift` — loop slice + crossfade seam.
- `Tests/loopedTests/Services/AudioFileServiceTests.swift` — the 20-min limit (pure
  `DefaultAudioFileService.exceedsDurationLimit`), error strings, a decode happy-path.

_View-models_ (behavior, via injected test doubles — automates most of the TESTING.md checklist):
- `Tests/loopedTests/ViewModels/PlayerViewModelTests.swift` — transport/looping/loading/seek intents
  against a `FakePlaybackService` spy + a real decoded fixture.
- `Tests/loopedTests/ViewModels/WaveformViewModelTests.swift` — scrubbing state + window delegation.
- `Tests/loopedTests/Support/TestDoubles.swift` — `FakePlaybackService`, `TooLongAudioFileService`,
  `AudioFixture` (writes a temp WAV). `Views/ContentViewTests.swift` — placeholder (empty).

The **audio engine** (`AVPlaybackService`) and the actual look/sound (loop seamlessness, waveform
smoothness) need a device/eyes/ears — see **`TESTING.md`** (repo root) for the manual QA checklist.

## Conventions

- SwiftUI-first; drop to AppKit (`NSViewRepresentable`) only for scroll and keyboard capture.
- **Layering**: `View → ViewModel → Service` (folders `Models/`, `Services/`, `ViewModels/`,
  `Views/`, `Utils/`). Views hold no logic; view-models hold `@Published` state + intents; services
  are plain (no SwiftUI) and sit behind protocols. Keep audio/UI-agnostic code out of the views and
  presentation state out of the services.
- **Dependency injection**: constructor injection wired at the composition root (`loopedApp`); no
  DI framework. New services get a `protocol` + a `Default…`/`AV…` implementation.
- State via `@Published` / `@EnvironmentObject` / `@StateObject` (Combine used mostly indirectly
  through `ObservableObject`).
- `async/await` for file I/O (`openFile`, `AudioFileService.load`).
- `// MARK:` section markers throughout.
- **SwiftFormat** config at repo-root `.swiftformat` — **tabs** for indentation, trailing commas
  always. Run `just format` before committing. (Note: `--redundant-async tests-only` strips `async`
  from `await`-less test methods — fine under SwiftPM, where sync `@MainActor` tests run cleanly.)
- **Theming**: use color tokens from `enum Theme` (`Sources/looped/Views/Theme.swift`) rather than
  hardcoded `Color`/`NSColor` literals in views.

## Maintenance — keep this file current

After **any** change that affects architecture, the file map, build/run commands, dependencies,
or conventions, **update the relevant section of this file in the same change**. This is enforced
by a `Stop` hook in `.claude/settings.json`: if Swift sources are modified but `CLAUDE.md` is not,
the hook blocks the turn with a reminder. Doc-only or no-op turns are unaffected.
