# Plan 3 — UI redesign (layout from the mock)

> **Status (2026-07-08): implemented, build-verified. Visual check pending.**
> Native SwiftUI throughout (`Slider` + `.tint`, `Button` + `.bordered`/
> `.borderedProminent`, SF Symbols, `@AppStorage`, animated `HStack` sidebar).
> Zero new files — helpers are `private struct`s (`Sidebar` in ContentView;
> `CompactSlider`/`LoopPanel` in ControlsView). Deferred to Plan 5: sidebar track
> list, and wiring the `«`/`»` loop-nudge arrows (laid out but disabled).
> Single "Pitch" slider = playback rate (per the mock). Verify in Xcode (⌘R).

**Type:** UI restructure + theming
**Depends on:** Plan 4 (done) — views bind to `PlayerViewModel`. `Theme` already
exists (`Views/Theme.swift`) from Plan 1 and gets expanded here.
**Primary files:** `ContentView.swift` (full re-layout), `ControlsView.swift`
(becomes the bottom bar), `loopedApp.swift`, `Theme.swift`, + new component/view files.

## Reference

Mock: `looped/plans/mockup/2026-07-08-ui-layout.png` (two states: sidebar open +
playing / collapsed + paused). Layout, top→bottom:

```
┌───────────────────────────────────────────────────────────┐
│ [⧉]  ┌─sidebar─┐        wizzy-waiters.mp3                   │  header: name + times,
│      │ import  │          02:20 | 4:20                      │  toggle icon top-left
│      │ file    │  ───────────────────────────────────────  │
│      │ track…  │                                            │
│      │ track…  │        ~~~ striped waveform ~~~            │  waveform (orange played)
│      │ (Plan 5)│                                            │
│      └─────────┘  ───────────────────────────────────────  │
│   ┌ Volume ────┐      ┌──┐ ┌──┐        ┌── Loop ───────┐    │  bottom bar
│   [====|=======]      │▶ │ │■ │        │ « (A) »        │   │
│   ┌ Pitch ─────┐      └──┘ └──┘        │ « (B) »        │   │
│   [======|=====]                       │ [Reset Loop]   │   │
│                                        └───────────────┘    │
└───────────────────────────────────────────────────────────┘
```

## Main differences vs current UI

1. **Collapsible left sidebar** with a top-left toggle icon + open/close animation.
   The **file browser/track list is Plan 5** — for now the sidebar holds just the
   **"import file"** button (the current Load button, moved here).
2. **Clean header** replaces the debug row: track name + `currentTime | fileTime`
   (`fileTime` = full duration at 1× / standard rate). Remove `Loaded:` text and the
   progress-%/raw-rate debug `HStack` (`ContentView.swift` header).
3. **Bottom-left**: `Volume` + `Pitch` sliders stacked in a compact wrapper (labels
   above each). No longer full-width.
4. **Bottom-center**: play/pause + stop, custom-styled.
5. **Bottom-right**: a bordered **Loop** panel — `A`/`B` buttons + `Reset Loop`.
   Each point is flanked by `«` / `»` **nudge arrows in the mock, but nudge is
   Plan 5** — Plan 3 lays out the panel and reserves space for the arrows; A/B/Reset
   work now, arrows get wired in Plan 5.

## Goal / desired behavior

- Dark, modern look (warm orange `#FF7A1A` accent on near-black), `.preferredColorScheme(.dark)`.
- Root layout = `HStack { Sidebar; MainColumn }`; sidebar collapses to zero width
  with animation, toggle persists top-left.
- Compact, role-sized sliders; custom transport + loop buttons; Loop panel in its
  own bottom-right card.
- Colors/metrics come from `Theme`, no scattered literals or native-blue tints.

## Approach

Presentation only — all state/logic stays on `PlayerViewModel` (Plan 4). New pieces:

### Theme (expand `Views/Theme.swift`)
- Add metrics: corner radius, control heights, standard padding, panel/border colors.
- Already has the palette; add any missing tokens (e.g. `panelBorder`, `controlTrack`).

### Components (new, `Views/Components/`)
- `IconButton` — SF Symbol button, themed, sized (transport + loop + toggle).
- `CompactSlider` — fixed-ish width, themed track + orange thumb, label above +
  optional value. Takes a `Binding`; **no domain math inside** (the rate log-scale
  stays in the view). Native `Slider` + `.tint` may suffice; fall back to a custom
  `Capsule` track if skinning is too limited.
- `Card`/`PanelBackground` modifier — surface fill + corner radius + subtle border
  (used by the Loop panel and slider wrapper).

### Views
- `SidebarView` (new) — animated collapsible container; contains the import button
  now, the track list later (Plan 5). Toggle state via `@State`/`@AppStorage`
  ("sidebarOpen") owned by `ContentView`.
- `PlayerHeader` (new or inline) — track name + `currentTime | fileTime`.
- `ControlsView` → the **bottom bar**: `HStack { slidersLeft; Spacer; transport;
  Spacer; LoopPanel }`. Split into `LoopPanelView` for clarity.
- `ContentView` — root `HStack(sidebar, mainColumn)`; overlay/lead the toggle icon
  top-left; `WaveformDisplayView` in the middle.

## Step-by-step

1. Expand `Theme` (metrics + any missing tokens); set `.preferredColorScheme(.dark)`
   and `Theme.background` at the root in `loopedApp`.
2. Build components: `IconButton`, `CompactSlider`, `Card`/`PanelBackground`.
3. `SidebarView` + collapse animation; move the "import file" button into it; wire
   the top-left toggle (`withAnimation`).
4. `PlayerHeader` with name + `TimeFormatter.mmss(currentTime) | TimeFormatter.mmss(duration)`.
5. Re-lay `ControlsView` into the 3-zone bottom bar; `LoopPanelView` (A/B/Reset, space
   reserved for Plan 5 nudge arrows); compact Volume/Pitch sliders bottom-left.
6. Rebuild `ContentView` root layout (sidebar + main column); empty state when no file.
7. Theme the waveform chrome (iterator/markers already use `Theme`); kill remaining
   `.blue` tints (`ControlsView`) and any stray literals.

## Files touched

- **New:** `Views/SidebarView.swift`, `Views/LoopPanelView.swift`,
  `Views/Components/{IconButton,CompactSlider,Card}.swift` (grouping TBD).
- **Changed:** `Views/ContentView.swift`, `Views/ControlsView.swift`,
  `Views/Theme.swift`, `looped/loopedApp.swift`.
- `CLAUDE.md` — file map (new views/components) + note the layout/sidebar.

## Risks & considerations

- **Custom slider skinning on macOS** — AppKit-backed `Slider` restyles poorly; may
  need a custom `Capsule` track for the mock look. Decide once building.
- **Sidebar approach** — custom animated `HStack` width (full control of the mock's
  toggle icon) vs `NavigationSplitView` (idiomatic, free collapse but native toggle
  styling). Leaning custom to match the mock.
- **"Pitch" slider — decided (2026-07-08):** Plan 3 keeps the **single existing
  slider controlling playback rate** (tempo/speed, pitch-preserved via
  `AVAudioUnitTimePitch.rate`), labeled "Pitch" per the mock. The richer control
  (independent Rate + Pitch sliders + a sync toggle for varispeed quality) is a
  **Plan 5** feature and replaces this single slider later.
- **Don't regress** the waveform: it lives between header and bottom bar and must
  keep its `GeometryReader` width correct as the sidebar animates (its
  `waveformWidth`/`contentWidth` depend on it) — verify pan math after collapse.

## Acceptance criteria

- [ ] Collapsible sidebar with top-left toggle + smooth open/close animation; holds
      the import button (list deferred to Plan 5).
- [ ] Header shows track name + `currentTime | fileTime`; debug row gone.
- [ ] Volume + Pitch sliders compact, stacked, bottom-left; transport centered;
      Loop panel (A/B/Reset) bottom-right in its own card.
- [ ] Dark orange/black theme applied app-wide; no native-blue tints; colors from `Theme`.
- [ ] Waveform pan/zoom stays correct as the sidebar collapses/expands and on resize.

## Open questions

- ~~Pitch slider behavior~~ — **decided**: single rate slider labeled "Pitch";
  independent pitch/rate + sync deferred to Plan 5 (see Risks).
- **Defaults applied unless told otherwise:** dark orange-on-black theme; sidebar
  remembers open/closed across launches (`@AppStorage`); Loop `« »` arrows laid out
  now but wired in Plan 5. Keep current `Theme` accent/neutral values.
