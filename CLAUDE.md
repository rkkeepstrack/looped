# CLAUDE.md — `looped`

## Overview

`looped` is a **macOS SwiftUI** audio-looping app: load an audio file (WAV / MP3 / AIFF), see an
interactive waveform, play it back with adjustable speed/pitch/volume, scrub the timeline, set
seamless **A/B loop points**. Spacebar toggles play/pause.

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
  `Stores/`, `ViewModels/`, `Views/`, `Utils/` (+ `Assets.xcassets`, excluded from the build).
- **`Tests/loopedTests/`** — unit tests (module `loopedTests`), mirroring the source folders.
- **`plans/`** — remaining-work docs (`README.md` first).

## Build & Run

Prerequisites: the **Command Line Tools** (`xcode-select --install`) and `brew bundle` (installs
`just` + `swiftformat`). Everything runs through **`just`** (see `justfile`); run `just` alone to
list recipes. Quickstart lives in `README.md`.

```bash
just build          # swift build (debug)
just run            # build a .app bundle (inlined in the justfile) and open it — proper GUI app
just test           # swift test — headless unit tests, no Xcode (pass args: just test --filter Looping)
just format         # swiftformat .   (just format-check to lint only)
just clean          # swift package clean + remove .build/Looped.app
```

`just run` assembles `.build/Looped.app` (an `Info.plist` + the SwiftPM binary) and `open`s it so it
launches as a real foreground app (Dock/menu/focus) — min window 1024×800, set in `loopedApp.swift`.
No asset catalog is compiled (`actool` needs Xcode) — no app icon / accent color via Info.plist.

## Architecture (SwiftUI + MVVM, DI'd services)

Layered **View → ViewModel → Store → Service** (+ `Models`), one-way dependencies.
`loopedApp.swift` (`@main`) is the **composition root**: it builds the services + store, injects
them via plain constructor injection (no DI framework), wires the advance-mode callback
(`PlayerViewModel.onAdvanceToNextTrack` → `LibraryViewModel.trackEnded()`, weakly captured — the
player must not retain the library) and the per-track parameter bridge
(`LibraryViewModel.captureParameters`/`applyParameters` ↔ `PlayerViewModel.currentParameters`),
and hands the view-models to the views as `environmentObject`s. Services sit behind protocols so
tests can fake them.

**Store** (`Stores/`, a UI-free `ObservableObject` both view-models depend on — the
library↔playback bridge; no VM→VM reference):

- **`PlaybackCoordinator`** — owns the current source (decode via `AudioFileService`, engine
  rewire, `loaded`) and the transport (play/pause/stop/seek, published clock/duration/load state,
  the 0.03s timer, `livePlaybackTime()`); end-of-track detection fires `onTrackEnded`
  (→ `PlayerViewModel.trackEnded()`, the playthrough-mode branch) and source changes fire
  `onSourceChanged` (per-track resets).

**View-models** (`ObservableObject`: `@Published` state + intents, no audio graph, no layout):

- **`PlayerViewModel`** — playback presentation: a thin projection of `PlaybackCoordinator`
  (transport state forwarded, `objectWillChange` re-published) plus the playback *parameters* —
  loop/rate/pitch/volume intents and loop-point state (cleared on `onSourceChanged`), the
  slider state bundled as `currentParameters` (a `TrackParameters` value, per-track via the
  library) — and the end-of-track policy: `playthroughMode` (loop / advance / stop, persisted in
  `UserDefaults`) branched in `trackEnded()`; advance defers to the library via the
  `onAdvanceToNextTrack` callback.
- **`LibraryViewModel`** — the track library: import panel, drag & drop intents
  (`handleLibraryDrop(providers:at:)`, `handleWaveformDrop(providers:)`), `add(urls:at:)` as the
  single intake (dedupe + `Track.isSupported` filter + `AVURLAsset` metadata, no decode),
  `move` (reorder), `load(_:)` bridging to the coordinator (no autoplay), and library-order
  transport: `next()`/`previous()`/`trackEnded()` (auto-advance) — the *decisions* (ordering,
  clamping, restart rule) are pure functions in `TrackNavigation`; the VM only executes the move.
  Owns persistence: `restore()` on launch, saves via `LibraryStore` on every mutation, stashes /
  applies each track's `TrackParameters` on switch (and on quit via `willTerminateNotification`).
- **`WaveformViewModel`** — waveform viewport state + scrub/snap-back gestures; delegates the
  window/analysis math to `WaveformService`.
- **`ReorderState`** — small observable owned by `TrackListView` (`@StateObject`, not injected):
  track-list drag state + gap decisions; boundary math delegated to `RowInsertion`.

**Services** (plain, protocol-backed, no SwiftUI; `Default…`/`AV…` naming):

- **`PlaybackService`** / `AVPlaybackService` — the audio player: engine graph
  (`player → timePitch → varispeed → mixer`), transport, loop scheduling, wall-clock-smoothed
  playback clock.
- **`AudioFileService`** — async URL → `LoadedAudio` decode; rejects tracks > 20 min
  (`AudioFileServiceError.tooLong` → `PlayerViewModel.loadError`).
- **`LoopingService`** — pure buffer DSP: slices [A, B) and crossfades the seam; also the plain
  tail `slice` used by the in-loop seek (injected into `AVPlaybackService`).
- **`DroppedFileService`** — drag & drop plumbing: `NSItemProvider` → URLs, recursive folder
  expansion filtered by `Track.isSupported`.
- **`WaveformService`** — pure waveform math: whole-song analysis, bucket-aligned window slice,
  overview downsampling; hosts `OverviewMapper` (strip-pixel ↔ song-time math for the minimap).
- **`LibraryStore`** / `JSONLibraryStore` — library persistence: track list + per-track
  parameters + last selection as JSON in Application Support; drops missing files on load.

**Models:** `LoadedAudio` (decoded file/buffer/format/duration). `Track` (library entry; also hosts
`supportedTypes`/`isSupported(url:)`, the single audio-type predicate shared by panel, intake, and
drop expansion). `TrackParameters` (per-track slider state: rate/pitch/volume/sync).

## File map

One line per file; the *why* behind non-obvious designs lives in the next section.

| File | Role |
|---|---|
| `loopedApp.swift` | `@main`; composition root; window sizing, dark scheme. |
| `Models/LoadedAudio.swift` | Decoded audio value type. |
| `Models/Track.swift` | Library entry + the shared supported-audio-type predicate. |
| `Models/PlaythroughMode.swift` | End-of-track mode (loop / advance / stop) + cycle order. |
| `Models/TrackParameters.swift` | Per-track slider state value (rate/pitch/volume/sync). |
| `Services/PlaybackService.swift` | Audio graph, transport, loop scheduling, playback clock. |
| `Services/AudioFileService.swift` | Async decode; 20-min limit. |
| `Services/LoopingService.swift` | Pure loop-buffer slice + seam crossfade. |
| `Services/DroppedFileService.swift` | Drop providers → URLs; folder expansion. |
| `Services/WaveformService.swift` | Pure waveform analysis + viewport window math + overview downsampling/mapper. |
| `Services/LibraryStore.swift` | Library persistence protocol + JSON impl (Application Support). |
| `Stores/PlaybackCoordinator.swift` | Playback store: source + transport + clock timer; track-ended/source-changed callbacks. |
| `ViewModels/PlayerViewModel.swift` | Transport projection + split play/pause + loop/rate/pitch/volume intents; `currentParameters` bundle; persisted playthrough mode. |
| `ViewModels/LibraryViewModel.swift` | Library state/intents; play bridge; next/previous/auto-advance; restore/save + per-track parameter stash. |
| `ViewModels/WaveformViewModel.swift` | Waveform viewport state; scrub/snap-back. |
| `ViewModels/ReorderState.swift` | Observable track-list drag state: reorder gap decisions, external drop gap. |
| `Views/ContentView.swift` | Root layout: sidebar (collapsible, resizable, `@AppStorage`), header, waveform (= quick-load drop zone), minimap strip, bottom bar; hosts `KeyboardHandler`. |
| `Views/SidebarView.swift` | Left panel: import button + playthrough-mode button, empty-state drop zone, hosts `TrackListView`. |
| `Views/PlaythroughModeButton.swift` | Cycling end-of-track mode button (icon + tooltip per mode); moves to the transport in plan 07. |
| `Views/TrackListView.swift` | Hand-rolled track list (+ private `TrackRow`, drop delegate): themed selection, drag-reorder, insertion indicator. |
| `Views/ControlsView.swift` | Bottom bar: volume/rate/pitch sliders + sync checkbox, transport (prev/play/next/stop), A/B `LoopPanel` with nudge arrows. |
| `Views/WaveformView.swift` | `WaveformDisplayView`: windowed two-layer waveform render, scrub highlight, A/B markers, center playhead. |
| `Views/MinimapView.swift` | Full-track minimap strip: whole-song envelope, viewport highlight box (drag = scrub, outside click = seek), loop tint. |
| `Views/SyncWaveformCanvas.swift` | Synchronous DSWaveformImage canvas shared by the main waveform and the minimap. |
| `Views/Theme.swift` | Design tokens: palette, waveform colors, layout metrics. |
| `Views/ScrollObserverView.swift` | `NSViewRepresentable`: scroll-wheel + mouse-drag capture → `WaveformViewModel`. |
| `Utils/KeyboardHandler.swift` | `NSViewRepresentable` key monitor; spacebar → play/pause. |
| `Utils/TimeFormatter.swift` | `m:ss` time formatting. |
| `Utils/RowInsertion.swift` | Pure gap-index math for list reorder/drop (gap N = space above row N; matches `Array.move` offsets). |
| `Utils/TrackNavigation.swift` | Pure library-transport policy: next/previous move decisions, 3 s restart rule. |

**Build/tooling:** `Package.swift` (deps DSWaveformImage + `swift-testing` pinned `.exact("6.1.3")`),
`justfile` (the `bundle` recipe assembles the `.app`), `.swiftformat`, `Brewfile`, `README.md`.

## Design rationale & gotchas (the "why" — don't re-litigate without reason)

- **Seamless A/B loops**: the [A, B) region is sliced out of the buffer and scheduled with
  `AVAudioPlayerNode`'s `.loops`; `LoopingService` crossfades the seam — a hard cut clicks and
  makes `AVAudioUnitTimePitch` warble, especially off 1× speed. Scrubbing while a loop is armed
  stays inside the loop: seeks within [A, B] move the loop phase (`seekInLoop` schedules the
  iteration's tail once, then the loop again; a phase offset keeps the folded clock aligned),
  seeks outside snap back; seeks are clamped to file bounds (out-of-range seeks crashed the player).
- **Engine rewires stop the engine first** (`setSource`): reconnecting a running engine races the
  render thread and crashes on the second track. Overlapping load requests are dropped in
  `LibraryViewModel.load` (a double-click fires two taps) for the same reason.
- **Playback clock**: the player node counts *source* frames upstream of both effect units,
  consumed at `timePitch.rate × varispeed.rate`; the clock projects onto the wall clock via the
  render timestamp's host time and low-pass filters, else the UI quantizes to the ~6–12ms render
  cycle.
- **Waveform rendering**: a windowed slice re-evaluated per display frame via
  `TimelineView(.animation)` + `PlayerViewModel.livePlaybackTime()` (the 0.03s timer only feeds
  labels). The canvas draws **synchronously** (`SyncWaveformCanvas`, a `WaveformLiveCanvas` clone)
  so the reslice and its compensating offset commit in one pass — the library's async canvas
  lagged a frame and made the seam flicker.
- **Minimap (full-track overview)**: box-drag is a scrub (it feeds the same `WaveformViewModel`
  scroll-offset/anchor machinery, converted from strip pixels) and the release **seeks** to the
  dropped position — identical semantics to the big waveform's scrub, incl. snap-back when the
  seek is refused (loop armed / out of bounds). A stationary click *outside* the box seeks via
  `PlayerViewModel.jumpTo`; a click inside the box is deliberately inert (grabbing the box must
  not jump playback). Envelope = analyzed samples downsampled per-bucket **min** (samples are
  inverted dB, 1 = silence) so peaks survive; rendered filled, not striped.
- **The track list is hand-rolled** (`TrackListView`, plain `VStack`, not `List`): the NSTableView under a native
  List draws its selection highlight and drop insertion indicator in the system accent color with
  no public recolor API, which clashed with the theme. Reorder drag is a per-row
  **high-priority** `DragGesture` (a plain/tap-ordered gesture loses arbitration and the row needs
  a hard pull to pick up); external drops go through a `DropDelegate` on the list *content* (not
  the ScrollView) so drop coordinates survive scrolling. Cost accepted: no keyboard list
  navigation, no auto-scroll while dragging.
- **List interactions**: single click selects (visual only), double-click loads, **no autoplay**
  anywhere — the transport starts playback.
- **Library transport**: next/previous move in list order, clamped (no wrap), **preserving the
  play state** (playing stays playing; paused stays paused — the no-autoplay rule). Previous
  restarts the current track when > 3 s in (standard player convention); on the first track it
  always restarts; with an A/B loop armed the restart jumps to the loop's A point instead
  (`PlaybackService.restartLoop`) — a silent no-op read as a broken button.
- **Playthrough modes** (what happens at end of track): one cycling button (sidebar-hosted until
  plan 07; warm-yellow `Theme.controlActive` icon = "engaged state", not selection-orange; the
  app-wide `NSInitialToolTipDelay` default is lowered at the composition root so its `.help`
  tooltip shows promptly) picks loop / advance / stop. The branch lives in `PlayerViewModel.trackEnded()` (intent
  layer): the coordinator has already stopped (playhead at 0), so *stop* is done, *loop* just
  plays again, *advance* fires `onAdvanceToNextTrack` → the library plays the next track (the
  last track just stops). Default **advance**; persisted as a `UserDefaults` scalar (app-wide, not
  per track — it doesn't belong in the JSON store). A looping track never "ends" (an armed A/B
  loop repeats forever), so the mode can't fire mid-loop.
- **Library persistence**: JSON at `Application Support/looped/library.json` — tracks (plain
  paths: the `just bundle` app is unsigned/unsandboxed, so paths stay readable; revisit with
  security-scoped bookmarks if ever sandboxed), last selection, and each track's
  `TrackParameters`. Saved synchronously on every mutation (the file is tiny); slider tweaks are
  only stashed into the track on a **switch or quit** — not per drag (deliberate: fewer writes).
  Missing files are dropped silently on load. Restore is latched to run once (`.task` re-fires on
  window recreation) and loads the last track without autoplay. The sliders bind through
  `PlayerViewModel` (no view-local `@State`) so applied per-track values actually show.
- **Rows have a fixed height** (`Theme.trackRowHeight`) so `RowInsertion`'s gap math stays trivial.

## Tests

Headless via `just test` — no Xcode, no app host, no audio device (~0.03s once built). Swift
Testing comes from the pinned `swift-testing` source dependency. Gotchas: the first build compiles
swift-testing + SwiftSyntax from source (slow once, then cached); **switching toolchains**
(CLT ↔ Xcode) needs `just clean` — the macro plugin cache is toolchain-specific.

Two layers, mirroring the source folders:

- _Pure logic_: `WaveformServiceTests`, `LoopingServiceTests`, `AudioFileServiceTests` (20-min
  limit), `DroppedFileServiceTests` (folder expansion over a temp fixture tree; provider resolution
  stays a manual check — needs a live drag pasteboard), `LibraryStoreTests` (round-trip +
  missing-file filter over a temp dir), `RowInsertionTests` (gap math),
  `TrackNavigationTests` (transport policy).
- _View-model behavior_ via the doubles in `Support/TestDoubles.swift` (`FakePlaybackService` spy,
  `FakeLibraryStore`, `TooLongAudioFileService`, `SlowAudioFileService` for overlapping-request
  tests, `AudioFixture` temp WAVs): `PlaybackCoordinatorTests` (end-of-track via the exposed
  `tick()` — no run-loop spinning), `PlayerViewModelTests` (incl. split play/pause and playthrough modes, driven via
  the coordinator's `tick()`; ephemeral `UserDefaults` suite per instance),
  `LibraryViewModelTests` (incl. next/previous/auto-advance, restore + parameter stash),
  `WaveformViewModelTests`, `ReorderStateTests` (drag latching, no-op slots, external-gap precedence).

The audio engine and the actual look/sound (loop seamlessness, waveform smoothness) need
device/eyes/ears — see **`TESTING.md`** (repo root) for the manual QA checklist.

## Conventions

- SwiftUI-first; drop to AppKit (`NSViewRepresentable`) only where SwiftUI can't (scroll/keyboard
  capture).
- **Layering**: `View → ViewModel → Store → Service`. Views hold no logic; view-models hold
  `@Published` state + intents; stores are UI-free observables shared across view-models; services
  are plain (no SwiftUI) and sit behind protocols. Keep UI-agnostic code out of views and
  presentation state out of services.
- **Dependency injection**: constructor injection wired at the composition root (`loopedApp`); no
  DI framework. New services get a `protocol` + a `Default…`/`AV…` implementation.
- `async/await` for I/O; `// MARK:` section markers throughout.
- **SwiftFormat**: repo-root `.swiftformat` — **tabs**, trailing commas. Run `just format` before
  committing. (`--redundant-async tests-only` strips `async` from `await`-less test methods — fine
  under SwiftPM.)
- **Theming**: use `enum Theme` tokens, never hardcoded `Color`/`NSColor` literals in views.
- **Naming**: view structs carry a kind suffix (`…View`, or `…Row`/`…Panel` for parts); screen-scoped,
  service-bearing observables are `…ViewModel`; small view-owned `@StateObject` observables are
  `…State` (e.g. `ReorderState`).
- **Workflow**: build + test, then present changes for the user's review — **commit only on their
  explicit go-ahead**.

## Maintenance — keep this file current

After **any** change that affects architecture, the file map, build/run commands, dependencies, or
conventions, **update the relevant section in the same change**. Enforced by a `Stop` hook in
`.claude/settings.json`: if Swift sources change but `CLAUDE.md` doesn't, the turn is blocked with
a reminder. Doc-only turns are unaffected. **Keep the altitude**: file-map entries stay one line
(what, not how — the code answers "how"); durable "why"s go in *Design rationale & gotchas*;
don't mirror implementation detail that churns with every commit.
