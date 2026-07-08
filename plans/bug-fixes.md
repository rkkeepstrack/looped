# Bug fixes

Open items only (fixed ones removed — see git history). Numbering is for reference,
not priority.

1. **Scrub highlight.** While scrubbing there's no indication of where you're scrolling
   to. Want a soft highlight in a slightly dimmer orange than the played part that
   follows the scrub cursor, overwriting the played-color when scrubbing backwards.
2. **Pitch vs. currentTime / waveform scroll.** Changing pitch/rate desyncs `currentTime`
   and how the waveform scrolls, which then breaks the loop points. (Tied to the
   pitch/rate work in the player-features plan.)
3. **Live slider labels.** The Pitch and Volume sliders should show the current value in
   place of the label while dragging, trimmed to a human-friendly value.
4. **Scrub should hold the playhead.** While scrubbing, the playhead should stay fixed at
   the current time and the audio should scroll out of view under it — rather than the
   pointer scrolling along with the audio.
5. **Waveform flickers during playback.** The windowed renderer (on `main`, commit
   `814d7f1`) flickers at regular-ish intervals while playing. The pre-windowing version
   `6436bca` is smooth but caps width (~12000px → no long songs at zoom). The A/B choice
   is still open.
6. **Display-synced smooth pan.** Drive the waveform pan from `TimelineView(.animation)`
   so it advances per display frame instead of the 0.03 s refresh timer (smoother scroll;
   may also help #5).
