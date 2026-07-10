# Bug fixes

Open items only (fixed ones removed — see git history). Numbering is for reference,
not priority.

1. **Main waveform flicker (again?)** — noticed 2026-07-10 while testing the full-track
   preview (plan 04): the main waveform seems to flicker during playback despite the
   synchronous `SyncWaveformCanvas` (bug-fixes #5 fix) — possibly the sync canvas never
   fully fixed it, or the added minimap changed the render timing. Needs a fresh look
   (video QA via ffmpeg frame diffs); verify whether `SyncWaveformCanvas` actually earns
   its keep.
2. Waveform looks a bit boring. I would like a peak morph algorithm, that if a waveform is equally loud for a certain time, you can still see louder and quieter parts more easily. The reason: Identify good loopable sections better as a musician instead of guessing where to put the loop points. probably some logarithmic stuff.
3. In the Live Waveform, always render the center line that shows where L/R Channels are split. maybe a subtle grey is enough.
4. when resetting the loop, the playback is stuck for like 0.2s, it's audible, not really annoying but the experience could be smoother

(Last fixed 2026-07-10 — sidebar-toggle waveform jump, via the grow-now/shrink-later
viewport-width policy in `WaveformViewModel`. Batch before — scrub highlight, pitch/rate clock desync, live slider labels, scrub
playhead behavior — fixed/resolved 2026-07-09; the scrub highlight ended up light blue
per feedback, and the playhead stays centered by design.)
