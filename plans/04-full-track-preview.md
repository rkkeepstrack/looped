# 04 — Full-track waveform preview (minimap)

Depends on: nothing (independent of the library plans).
Mockup: `mockup/ui-small-waveform-view.png`.

## What

A second, small waveform strip directly **below** the main waveform showing the **entire
song** at once, with a highlight box marking the section currently visible in the big
waveform — a minimap, like the overview strip in DAWs/Audacity.

## Behavior

- **Highlight box** = the big waveform's visible window, in song coordinates. It moves
  in sync with playback (and with any scrolling/scrubbing of the big waveform), since
  the big view's viewport is what it mirrors.
- **Shared highlight states** (best-effort, same visual language as the big view):
  the already-played portion tinted orange (`Theme` played color) up to the playhead,
  and the scrub highlight (light blue) while a scrub is in progress.
- **Drag the highlight box** → *scrub only*: moves the big waveform's viewport exactly
  like scrolling it (latches the scrub anchor; playback keeps running; snap-back rules
  unchanged). Lets the user peek ahead without losing their place.
- **Click elsewhere on the strip** → *seek*: playback jumps to the clicked time
  (`PlayerViewModel.jumpTo`), clamped to file bounds; loop-armed seek semantics stay
  as they are today (stay inside the loop while armed).

## Implementation notes

- `WaveformService.analyze` already produces the whole-song envelope; the minimap can
  reuse the same `samples` downsampled to the strip's width — no second decode. Add a
  pure helper (e.g. `overviewSamples(samples:targetWidth:)`) to `WaveformService` so
  it stays testable.
- New private view in `Views/` (e.g. `TrackOverviewView`) rendered with the existing
  `SyncWaveformCanvas` approach; box position/width derive from `WaveformViewModel`'s
  layout + `currentScrollOffset` / `window(playbackTime:)`.
- Mouse handling can go through a small `NSViewRepresentable` or SwiftUI gestures —
  it's click/drag only (no scroll-wheel), so SwiftUI `DragGesture` should suffice.
- Colors from `enum Theme`; add tokens if new ones are needed.

## Tests

- Window→box mapping and click→time mapping as pure functions in `WaveformService`
  (or a small mapper type) — unit-test bucket/pixel math like `WaveformServiceTests`.
- View-model: drag routes to scrub (viewport moves, no seek), click routes to `jumpTo`.
