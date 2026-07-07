# Plan 1 — Waveform rendering (SoundCloud-esque stripes)

> **Status (2026-07-07): implemented, build-verified. Visual/runtime check pending.**
> Rewrote `WaveformView.swift`; added `Theme.swift`. Builds clean
> (`DEVELOPER_DIR=/Applications/Xcode.app/... xcodebuild … BUILD SUCCEEDED`, no
> warnings). Remaining: confirm the look with a loaded file in Xcode (⌘R) and pin
> the palette with Plan 3.

**Type:** Bug (not rendering / dead code) + visual feature
**Depends on:** lightly on Plan 4 (final type of the `waveform` property / where
presentation math lives). Can proceed before 4 with minor rework later.
**Primary file:** `looped/Views/WaveformView.swift` (`struct WaveformDisplayView`)

## Problem

The waveform doesn't render as intended and the view is full of commented-out
code. Desired look: **SoundCloud-style striped bars with small gaps** (not a solid
filled shape), with a clear played-vs-unplayed distinction, in the app's warm
orange on black.

## Root cause / current state

`WaveformView.swift` renders via **DSWaveformImage** but is in a half-finished state:

- Line 31 draws a single striped `DSWaveformImageViews.WaveformView` offset by the
  center-iterator math. This is the *only* live layer.
- Lines 33-66 are **commented-out** dead code: the "Progress View" overlay, a
  `LinearGradient` fill for played/unplayed coloring, and the A/B loop markers.
  This is almost certainly what "the waveformView is commented out" refers to.
- Line 24 hardcodes `color: .red` — wrong palette (Plan 3 wants orange).
- The played/unplayed visual distinction is entirely gone (only commented remains).
- Build state could not be verified from the CLI (no Xcode toolchain in the agent
  env); **verify in Xcode**. Watch for `WaveformView` name ambiguity now that the
  local struct is `WaveformDisplayView` — line 31's bare `WaveformView` should
  resolve to `DSWaveformImageViews.WaveformView`, but qualify it explicitly to be safe.

## How the scrolling model works (context)

`OffsetCalculator.calculateOffsetForWaveform` (`OffsetCalculator.swift:49-69`) pans
the whole waveform horizontally so the "now" position sits under a fixed **center
iterator** (the yellow `Rectangle`, line 68). At progress *p*, offset =
`width/2 − p·width (+ scrollOffset)`. So **everything left of center is "played."**
That fixed-center design dictates how we color progress (see below).

## Goal / desired behavior

1. Striped waveform with small gaps between bars (SoundCloud look), warm orange.
2. Played portion visually distinct from upcoming portion (e.g. bright orange
   played, dimmed/gray upcoming), split at the center iterator.
3. A/B loop markers + shaded loop region drawn on the waveform (re-enable the
   commented feature) — coordinate visuals with Plan 2.
4. All dead/commented code removed.

## Approach

DSWaveformImage's `.striped` style already gives the bars/gaps. It has no built-in
"progress" mask, so use the **two-layer overlay** technique (classic SoundCloud):

- **Base layer:** full striped waveform in the *dimmed/upcoming* color.
- **Highlight layer:** identical striped waveform in *bright orange*, **masked to
  the region left of the center iterator** (screen-space mask, since "played" is
  always left of center in this design).

Stripe config (tune to taste):

```swift
Waveform.Configuration(
    style: .striped(.init(color: NSColor(<upcoming>), width: 2, spacing: 3, lineCap: .round)),
    verticalScalingFactor: 0.5,
    shouldAntialias: true
)
```

`width`/`spacing` control bar thickness and gap. Two configs (dimmed + bright) or
one waveform tinted via an overlay + `.mask`.

## Step-by-step

1. **Delete** all commented blocks (lines 33-66 region) and the stray old
   `DSWaveformImageViews.WaveformView { … }` closure remnants.
2. Extract stripe/palette constants (colors from the Plan 3 palette;
   see `Theme`). Avoid hardcoded `.red`.
3. Render **base** striped waveform (upcoming color) offset by
   `calculateOffsetForWaveform(...)`.
4. Render **highlight** striped waveform (played color), same offset, wrapped in a
   `.mask { }` / overlay clipped to `x <= centerX` so only the played part shows
   bright. Use `GeometryReader` width and the center split.
5. Re-enable **A/B markers**: thin vertical bars + "A"/"B" labels positioned via
   `calculateOffsetForLoopPoint(time:duration:)` (`OffsetCalculator.swift:71-76`),
   plus a translucent orange rectangle spanning [A,B] as the loop region.
6. Keep the center iterator (line 68) but restyle to the theme (thin orange line).
7. Keep the `ScrollObserverView` wiring (lines 76-89) unchanged.
8. Confirm `offsetCalculator.waveformWidth` is set on appear **and** on resize
   (`.onAppear` at line 70 only fires once — consider `onChange(of: geo.size)`),
   otherwise the offset math is wrong after a window resize.

## Files touched

- `looped/Views/WaveformView.swift` (primary rewrite of `body`).
- `looped/Services/OffsetCalculator.swift` — reuse existing loop-point/offset math;
  may add a small "played width" helper.
- `Theme` (new, shared with Plan 3) for colors.
- `CLAUDE.md` — `WaveformView` row already notes the struct name; update if the
  rendering approach/description changes materially.

## Risks & considerations

- **`waveform: Any?`** on `AudioEngineController` (`AudioEngineController.swift:21`)
  is an untyped placeholder and is **not** used for rendering (DSWaveformImage reads
  the URL directly). Either type it properly or delete it — resolve in Plan 4.
- **Performance:** two `WaveformView`s re-render on every offset change (0.03 s
  timer). DSWaveformImage renders async and caches by URL+config, so two static
  layers + a moving `.offset`/`.mask` is cheap. Verify no re-decode per tick.
- **Masking in a panning coordinate space** is the fiddly part — the mask is
  screen-space (left of center), while the waveform moves; keep the mask fixed and
  let the waveform slide under it.
- **Name ambiguity**: qualify `DSWaveformImageViews.WaveformView` explicitly.

## Acceptance criteria

- [~] Loaded file shows striped bars with visible gaps — *implemented* (striped
  config, width 2 / spacing 2); confirm visually.
- [~] Played portion (left of center) bright orange, upcoming dimmed —
  *implemented* via a played-layer masked to `[0, progress·width]`; confirm visually.
- [~] A/B markers + shaded loop region — *implemented*; confirm once Plan 2 sets
  loop points at runtime.
- [x] No commented-out code remains in `WaveformView.swift` (full rewrite).
- [x] Waveform stays correct after window resize (`onChange(of: width)` added).

## Follow-ups done (2026-07-07)

- **Perf:** at zoom 12 the single re-stroked `WaveformView` stuttered hard. Split
  into a private, `Equatable`, `.drawingGroup()`-cached `StripedWaveform` (two
  layers: upcoming + played-masked) so the striped path is only rebuilt on
  url/width/color/floor change, not every playhead tick.
- **Peak emphasis:** the waveform looked "evened out." `StripedWaveform` now runs
  its own `WaveformAnalyzer` with `noiseFloorDecibelCutoff` (`waveformNoiseFloor`,
  default −35 dB) — higher floor compresses the visible range so peaks stand out.
  Tunable constant; may want a UI control (Plan 3).

## Open questions

- Exact palette split (played vs upcoming shades) — pin down with Plan 3.
- Does −35 dB noise floor look right, or want it punchier (−30) / gentler (−42)?
- ~~Should the waveform be scroll-zoomable, or fixed to fit width?~~ **Resolved
  (2026-07-07):** added a `zoom` factor to `OffsetCalculator`
  (`contentWidth = waveformWidth * zoom`, default 6) so the waveform renders wider
  than the viewport and pans faster. A user-facing zoom control is deferred to Plan 3.
