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
