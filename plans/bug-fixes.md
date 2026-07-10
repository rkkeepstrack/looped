# Bug fixes

Open items only (fixed ones removed — see git history). Numbering is for reference,
not priority.

1. **Main waveform flicker (again?)** — noticed 2026-07-10 while testing the full-track
   preview (plan 04): the main waveform seems to flicker during playback despite the
   synchronous `SyncWaveformCanvas` (bug-fixes #5 fix) — possibly the sync canvas never
   fully fixed it, or the added minimap changed the render timing. Needs a fresh look
   (video QA via ffmpeg frame diffs); verify whether `SyncWaveformCanvas` actually earns
   its keep.
2. When opening and closing the sidebar, the waveformviews jumps instead of transforming with the animation. Maybe during the animation phase, just add a scaling/transformation animation effect to the waveform and when the animation is completed initiate the jump/rerender/refresh?

(Last batch — scrub highlight, pitch/rate clock desync, live slider labels, scrub
playhead behavior — fixed/resolved 2026-07-09; the scrub highlight ended up light blue
per feedback, and the playhead stays centered by design.)
