# Bug fixes

Open items only (fixed ones removed — see git history). Numbering is for reference,
not priority.

(No open items.)

(Last fixed 2026-07-10 — #1 main waveform flicker: diagnosed via ffmpeg frame diffs as
temporal aliasing (strobing) of the 4 pt stripe pattern under the smooth ~1.7 px/frame
pan — not a render-timing bug; `SyncWaveformCanvas` earns its keep (the seam was
stable). Fixed by quantizing the window offset to whole stripe pitches in
`WaveformService.window` — screen-fixed bars, content flows through them. Before that,
same day — #2 waveform peak morph (`WaveformService.peakMorph` power
curve, main waveform only), #3 waveform midline (`Theme.waveformCenterline`), #4
loop-reset audio gap (in-memory bridge in `AVPlaybackService.clearLoop`). Before
that, same day — sidebar-toggle waveform jump, via the grow-now/shrink-later
viewport-width policy in `WaveformViewModel`. Batch before — scrub highlight, pitch/rate clock desync, live slider labels, scrub
playhead behavior — fixed/resolved 2026-07-09; the scrub highlight ended up light blue
per feedback, and the playhead stays centered by design.)
