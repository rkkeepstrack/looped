# 07 — Bottom-bar / controls redesign (toolbar)

Depends on: **01 (track library)**, **03 (transport)**, **05 (end-of-track modes)**.
Scope: the playback/mode/open functionality already exists by then — this plan is UI:
new controls, layout, and wiring. Plus a native menu bar and A/B marker labels.

## Problems with the current bottom bar

- The two transport buttons look sparse/awkward; play/pause is one toggle button.
- The three horizontal sliders stacked vertically feel clunky.
- The bar is too tall ("chonky") for the otherwise sleek design.
- Left/center/right alignment falls apart on wide windows — the groups look lost.

## New layout — one centered cluster

Everything sits in a **single horizontally centered group** with fixed gaps; nothing is
pinned to the window edges (wide windows just get symmetric empty margins). Target a
noticeably **slimmer bar height** than today.

```
├──────────────────────────────────────────────────────┤
│      VOL ─▮─   RATE  ─▮─ ⌉                            │
│                PITCH ─▮─ ⌋↻   [▶][⏸][⏹][mode][📂]  A·B │
└──────────────────────────────────────────────────────┘
```

Cluster contents, left to right:

1. **Volume slider** — standalone, as today (live value label and
   click-label-to-reset stay).
2. **Rate + Pitch as a compact VStack** — the two sliders stacked tightly, with the
   **sync button beside the pair**: a small arrow/bracket icon that visually *connects*
   the two sliders and **lights up yellow when sync is enabled** (replaces the current
   "Sync pitch & rate" checkbox; same varispeed semantics — synced: rate drives both,
   pitch slider disabled showing the implied shift).
3. **Transport toolbar** (replaces the current two buttons):
   - **Play** — resumes if paused; if already playing, restarts the track from the
     start; if loop points are set, the loop resets (playhead back to A).
   - **Pause** — pauses at the current time; no-op if already paused.
   - **Stop** — stops and resets the playhead to the start (existing behavior).
   - **Mode button** — the `PlaythroughModeButton` from plan 05, *moved here from the
     sidebar* (icon cycles loop/advance/stop, native `.help` tooltip).
   - **Open file** — opens the file dialog; the chosen track is added to the library
     and loaded into the waveform view (same path as the sidebar import button — keep
     or drop the sidebar one, decide during implementation).
4. **Loop panel (A·B)** — as today, restyled to match the slimmer bar if needed.

## Also in this plan

- **A/B labels on the waveform markers** — the loop-point markers in the big waveform
  get small "A" and "B" labels so they're identifiable at a glance (Theme colors).
- **Native macOS menu bar** — add `.commands` in `loopedApp`:
  - **File**: Open… (⌘O).
  - **Playback** (new menu): Play/Pause (space already works), Stop,
    playthrough-mode selection.
  - **Edit**: standard items suffice for now (nothing app-specific yet).

## Implementation notes

- All in `Views/ControlsView.swift` (+ small private subviews), `WaveformView.swift`
  (marker labels), `loopedApp.swift` (commands). No service changes expected.
- Icons: SF Symbols; colors/metrics via `enum Theme` (add a yellow "sync active" token).
- Play/pause split changes `PlayerViewModel` intents slightly: `play()` (with the
  restart-if-playing + loop-reset rule) and `pause()` alongside/instead of
  `togglePlayPause` — spacebar keeps toggling.

## Tests

- `PlayerViewModelTests`: play-while-playing restarts from 0 (and from A when a loop is
  armed); pause-while-paused is a no-op.
