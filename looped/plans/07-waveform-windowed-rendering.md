# Plan 7 — Waveform windowed ("live") rendering + length limit

> **Status (2026-07-08): core done, build-verified.** Windowed rendering shipped:
> whole song analyzed once, only a bucket-aligned viewport chunk is drawn via two
> `WaveformLiveCanvas` layers and translated via `.offset` (smooth, peaks stable);
> the analysis + window math live in a new pure `WaveformService`; 20-min limit +
> error in `AudioFileService`; eased snap-back on scrub release (manual per-frame).
> **Remaining:** bug #2 (dim-orange scrub highlight) and the **display-synced pan**
> (still ~33 Hz stepping — `TimelineView`), which also subsumes the snap-back timer.

**Type:** Waveform rendering rework (supersedes the `maxContentWidth` cap; folds in
Plan 5 #8 "display-synced pan"; keeps the SoundCloud look from Plan 1).
**Depends on:** Plans 1 & 3 (done).
**Primary files:** `Views/WaveformView.swift` (rewrite render path),
`ViewModels/WaveformViewModel.swift` (window math + master samples),
`Services/AudioFileService.swift` (length guard).

## Problem

The waveform is drawn as one big layer `contentWidth` wide and rasterized via
`.drawingGroup()`. That doesn't scale:

- At 2× backing scale, `contentWidth = 12000 pt → 24000 px` texture — already past
  the ~**16384 px** Metal max, so it's tiled/downscaled (part of why it feels heavy).
- Full-render at a usable zoom (`pixelsPerSecond ≈ 100`) tops out at **~80 s** before
  hitting that ceiling; a **20-min song would be ~120000 px / ~460 MB** — non-viable.
- The `maxContentWidth = 12000` cap "fixes" this only by squishing long songs to
  uselessly low resolution / very slow scroll.

The sample **data**, by contrast, is tiny: 20 min at ~200 samples/s ≈ **<1 MB**.
It's the bitmap that's expensive, not the analysis.

## Goal

- Render cost **constant** (≈ viewport-sized) regardless of song length.
- Support songs **up to 20 minutes** at real zoom; **> 20 min → clear error**.
- Keep the current look: striped bars, orange played / gray upcoming split at the
  center iterator, A/B markers + shaded loop region, scrub + spacebar.
- Get **display-synced smooth panning** for free (Plan 5 #8 folds in here).

## Approach — use the library's `Canvas`-based live path

`WaveformLiveCanvas` (DSWaveformImageViews, macOS 12+) draws a `[Float]` array into a
`Canvas(rendersAsynchronously: true)` **sized to the view** (not a fixed huge layer).
`WaveformImageDrawer.draw` takes the last `viewportWidth × scale` samples, so if we
hand it exactly that many, it fills the viewport.

1. **Analyze once per song** → one master `[Float]` amplitude array at a chosen
   resolution (≈ `duration × samplesPerSecond`, sub-MB). Store in `WaveformViewModel`
   (with the `noiseFloorDecibelCutoff` for peak emphasis). Cheap; done on load.
2. **Render only the visible window.** Each frame, compute the sample slice around
   `currentTime` (± half a viewport of time given `pixelsPerSecond`), length
   ≈ `viewportWidth × scale`, and feed it to a viewport-sized `WaveformLiveCanvas`.
   Two layers (upcoming gray / played orange) + a center mask, as today.
3. **Pan = slide the window** through the master array as `currentTime` advances
   (plus a sub-pixel offset for smoothness). Playhead stays at viewport center.
4. **Display-synced:** drive the redraw with `TimelineView(.animation)` and
   interpolate `currentTime` from the last engine sample each frame → no 33 Hz
   stepping (replaces Plan 5 #8; keep the 0.03 s engine poll as source of truth).
5. **Loop markers / region + scrub** map into window coordinates (time → x within the
   visible window) instead of the full-content coordinate space.

## Length limit

- In `AudioFileService.load`, after reading duration, throw a typed error
  (e.g. `AudioFileServiceError.tooLong(maxMinutes: 20)`) when `duration > 20 min`.
- `PlayerViewModel.load` surfaces it (status message / alert). Note: the limit is a
  **product choice**, not a technical one (windowing handles longer fine) — easy to
  raise later.

## Step-by-step

1. `WaveformViewModel`: hold master `samples: [Float]` + `analyze(url:noiseFloor:)`
   (once per url, cached); expose `visibleSamples(currentTime:viewportWidth:)` and
   window→x mapping for loops/scrub. Drop `contentWidth`/`maxContentWidth`.
2. `WaveformView`: replace the offset-layer + `StripedWaveform` with viewport-sized
   `WaveformLiveCanvas` layers (upcoming + played-masked) fed the window slice.
3. Wrap in `TimelineView(.animation)`; interpolate `currentTime` per frame.
4. Re-map A/B markers, shaded region, center iterator, and scroll/scrub math to
   window coordinates.
5. `AudioFileService`: 20-min guard + typed error; surface in `PlayerViewModel`.
6. Verify loop, scrub, zoom, resize, sidebar toggle; update `CLAUDE.md`.

## Files touched

- `Views/WaveformView.swift` (render path rewrite; `StripedWaveform` likely removed).
- `ViewModels/WaveformViewModel.swift` (master samples + window math).
- `Services/AudioFileService.swift` (+ `PlayerViewModel` for the error surface).
- `CLAUDE.md`.

## Risks & considerations

- **Coordinate remap** (loops/scrub/scroll from full-content space → visible window)
  is the fiddly part; do it carefully and test scrubbing + loop-marker positions.
- **Drawer "last N samples" behavior** — must feed exactly `viewportWidth × scale`
  (pad with silence at the very start/end of the song).
- **Master resolution** — pick `samplesPerSecond` so zoomed-in detail stays crisp
  without a huge array (a few hundred/s is plenty; ~sub-MB for 20 min).
- **Per-frame redraw** via `Canvas` should be cheap (viewport-sized, async), but
  profile in a **Release** build; keep analysis off the main thread.
- **Playback smoothness** must not regress — the Equatable/`drawingGroup` caching
  goes away, replaced by the Canvas redraw; verify no stutter during playback.

## Acceptance criteria

- [ ] A 20-min song loads and scrolls at full zoom with no lag/texture issues.
- [ ] Render cost is ~constant across song lengths (viewport-sized).
- [ ] Waveform pan is smooth/display-synced (no 33 Hz stepping).
- [ ] Played/upcoming split, A/B markers, shaded region, scrub, spacebar all intact.
- [ ] Files > 20 min are rejected with a clear message; ≤ 20 min work.

## Open questions

- Master `samplesPerSecond` value (detail vs size)?
- Keep `pixelsPerSecond = 100` as the zoom, or expose a zoom control now?
- Exact 20-min error UX — inline status text vs alert?
