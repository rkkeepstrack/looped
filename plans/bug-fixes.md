# Bug fixes

Open items only (fixed ones removed — see git history). Numbering is for reference,
not priority.

1. **Main waveform flicker (again?)** — noticed 2026-07-10 while testing the full-track
   preview (plan 04): the main waveform seems to flicker during playback despite the
   synchronous `SyncWaveformCanvas` (bug-fixes #5 fix) — possibly the sync canvas never
   fully fixed it, or the added minimap changed the render timing. Needs a fresh look
   (video QA via ffmpeg frame diffs); verify whether `SyncWaveformCanvas` actually earns
   its keep.
(Last fixed 2026-07-10 — #2 waveform peak morph (`WaveformService.peakMorph` power
curve, main waveform only), #3 waveform midline (`Theme.waveformCenterline`), #4
loop-reset audio gap (in-memory bridge in `AVPlaybackService.clearLoop`). Before
that, same day — sidebar-toggle waveform jump, via the grow-now/shrink-later
viewport-width policy in `WaveformViewModel`. Batch before — scrub highlight, pitch/rate clock desync, live slider labels, scrub
playhead behavior — fixed/resolved 2026-07-09; the scrub highlight ended up light blue
per feedback, and the playhead stays centered by design.)
