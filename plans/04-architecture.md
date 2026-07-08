# Plan 4 — Architecture: separate function from design

> **Status (2026-07-07): DONE, build-verified.** Went with a service-oriented full
> split (the user's Spring mental model: a state-holder + injected services):
> - `AudioEngineController` → **`PlayerViewModel`** (state/intents/timer) driving three
>   protocol-backed services: **`PlaybackService`/`AVPlaybackService`** (graph + transport +
>   loop scheduling + clock), **`AudioFileService`** (async URL→`LoadedAudio` decode),
>   **`LoopingService`** (pure loop-buffer slice + crossfade).
> - `OffsetCalculator` → **`WaveformViewModel`** (renamed, moved to `ViewModels/`).
> - New `Models/LoadedAudio`, `Utils/TimeFormatter`; folders Models/Services/ViewModels/Views/Utils.
> - Constructor DI at the composition root (`loopedApp`); no DI framework.
> - **Dead code removed:** `waveform: Any?`, `rawSamples`, `pausedTime`,
>   `calculateGradientWhileScrolling`, and `AudioEngineBufferFunctions.swift`.
> - Decisions taken: **D1** = full split; **D2** = rename+move; **D3/D4/D5** = delete;
>   **D6** = do it up-front (before Plans 3 & 5). Views kept the same VM API surface to
>   minimize churn (a couple of legacy variable names like `offsetCalculator` remain).

**Type:** Refactor + **decision doc** (let's agree the target before coding)
**Depends on:** nothing, but should be settled *before* Plans 1, 3, 5 harden the
current shape.
**Scope:** whole app, mainly `Services/` and how `Views/` bind to it.

> This is the "examine and find a solution together" plan. It lays out the current
> coupling, a proposed target, and **decision points** for you. Nothing here is
> final until we pick options.

## Current structure (observed)

```
loopedApp (@main)
 ├─ AudioEngineController : ObservableObject   ← "the core"
 └─ OffsetCalculator      : ObservableObject   ← "Service" but pure view-math
      injected as environmentObjects into ContentView → {Waveform, Controls}
```

## Where function and design are intertwined

1. **`OffsetCalculator` is filed under `Services/` but is pure presentation math**
   (`OffsetCalculator.swift`): center-iterator panning, gradient positions,
   loop-point x-offsets. It's a *view-model for the waveform*, not a service. It
   also depends on `waveformWidth` — a pixel value — which is a UI concern living
   in a "service".
2. **`AudioEngineController` mixes layers** (`AudioEngineController.swift`):
   - Low-level audio graph (engine/player/timePitch, `init`, buffers).
   - Playback state machine (`isPlaying`, timers, `jumpTo`).
   - Loop logic (`checkLoop`, being fixed in Plan 2).
   - **Presentation-flavored published state**: `rawSamples` (line 38) and
     `waveform: Any?` (line 21, an untyped placeholder) — UI/data concerns leaking
     into the audio core. `waveform: Any?` isn't even used for rendering.
3. **Formatting lives in the View**: `formatDuration` (`ContentView.swift:56-64`)
   and the raw `String(format:)` readouts (lines 46-50) are presentation logic
   embedded in the layout.
4. **Value-mapping lives in the View**: the rate log-scale
   (`0.5 * pow(4, sliderPosition)`, `ControlsView.swift:33`) is domain math sitting
   in a button closure.
5. **Dead / legacy code**: `AudioEngineBufferFunctions.swift` is explicitly
   "legacy/alternative … not the active playback path" (CLAUDE.md) and uses
   `@Binding` on free functions — confusing and unused.
6. **`ContentView` owns `KeyboardHandler`** wiring (line 27) and a stray unused
   `let formatter` (line 16).

## Proposed target (MVVM with clear layers)

```
Model / domain
  Track                     value type: url, title, duration, …           (new; Plan 5)

Service (pure audio, no SwiftUI)
  AudioEngine               owns AVAudioEngine graph + primitives:
                            load/schedule/play/pause/seek/loop-buffer.
                            No @Published UI vanity state; exposes plain
                            callbacks or an async stream of engine events.

ViewModel (ObservableObject, @Published UI state)
  PlayerViewModel           isPlaying, currentTime, duration, rate, volume,
                            loopStart/End, currentTrack; formatting; rate
                            log-scale mapping; drives AudioEngine.
  WaveformViewModel         (= today's OffsetCalculator, renamed + moved out of
                            Services) center-iterator/offset/loop-point math.
  LibraryViewModel          tracks list, selection, drag-drop intake  (Plan 5)

View (SwiftUI, dumb)
  ContentView / ControlsView / WaveformDisplayView / LibraryView
  Theme + components                                                  (Plan 3)

Presentation utils
  TimeFormatter             formatDuration etc.
```

### Group/folder layout

```
looped/
  Models/         Track.swift
  Services/       AudioEngine.swift            (audio only)
  ViewModels/     PlayerViewModel.swift, WaveformViewModel.swift, LibraryViewModel.swift
  Views/          ContentView, ControlsView, WaveformDisplayView, LibraryView, Theme, components
  Utils/          KeyboardHandler, TimeFormatter
```

## Decision points (need your call)

- **D1 — How far to split `AudioEngineController`?**
  - (a) **Two layers**: `AudioEngine` (service) + `PlayerViewModel` (state/formatting).
    Cleanest separation; more wiring. *Recommended.*
  - (b) **Keep one class** but move presentation bits out (formatting, rate mapping,
    `rawSamples`/`waveform`) and rename honestly. Less churn, still coupled.
- **D2 — `OffsetCalculator`**: rename to `WaveformViewModel` and move to
  `ViewModels/` (recommended), or leave name and just move the file?
- **D3 — `waveform: Any?` (line 21)**: delete (recommended — unused), or type it as
  real sample/render data if we have a plan for it?
- **D4 — `rawSamples`**: keep on the engine, move to a waveform view-model, or drop
  if DSWaveformImage (URL-based) makes it redundant?
- **D5 — `AudioEngineBufferFunctions.swift`**: delete (recommended) or fold the one
  useful buffer-seek path into `AudioEngine`?
- **D6 — Scope now vs later**: do the full split up front, or refactor
  incrementally as Plans 1/2/3/5 touch each area?

## Step-by-step (assuming D1=a, incremental)

1. Introduce `PlayerViewModel` wrapping the existing controller; move `@Published`
   UI state, formatting, and rate mapping into it. Views bind to it.
2. Extract a pure `AudioEngine` service (graph + primitives) behind the view-model;
   no SwiftUI imports there.
3. Rename `OffsetCalculator` → `WaveformViewModel`, move to `ViewModels/`.
4. Add `Utils/TimeFormatter`; move `formatDuration` out of `ContentView`.
5. Delete `AudioEngineBufferFunctions.swift` and `waveform: Any?` (pending D3/D5).
6. Reorganize folders/groups; update `loopedApp` env-object wiring.
7. Update `CLAUDE.md` Architecture + File map + Conventions to match.

## Risks & considerations

- **Refactor churn vs the other plans** — agree D6 first so we don't rewrite the
  same files twice. If features (Plan 5) are urgent, do the split *with* them.
- **`@StateObject` ownership** stays in `loopedApp`; keep env-object injection so
  views don't change their access pattern much.
- **Don't over-engineer** — this is a small app; two clean layers + a couple of
  view-models is the sweet spot, not a full VIPER/coordinator stack.
- **The `CLAUDE.md` sync hook** will require doc updates in the same change.

## Acceptance criteria

- [ ] Audio (service) has no SwiftUI/presentation state; view-models hold UI state.
- [ ] Presentation math (offsets, formatting, rate scale) lives in view-models/utils.
- [ ] No dead code (`AudioEngineBufferFunctions`, `waveform: Any?`) unless justified.
- [ ] Folder groups reflect Model / Service / ViewModel / View / Utils.
- [ ] `CLAUDE.md` matches the new structure.

## Open questions

- Answers to **D1–D6** above.
- Is there a future plan for `waveform`/`rawSamples` that argues for keeping them?
