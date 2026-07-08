# Plan 6 — Bug fixes

1. ✅ **Done.** When scrolling through the audio, the Player can go out of bounds and then crash. when scrolling and then letting go of the scrolling in an out of bounds state, the currentTime should just continue playing as before and a swift native animation should be played that brings the scrubbing cursor back to the played audio.
   → No crash (seek is bounds-clamped); an out-of-bounds release keeps playing as before; eased snap-back animation added (`Theme.scrubSnapBack`, `.easeOut`).
2. ⬜ **→ Plan 7.** when scrolling through the audio, there is currently no highlight to where i'm scrolling to. i would like a soft highlight in a slightly dimmer orange than the already played part, that follows where i'm scrubbing to. the dim orange should overwrite the color that indicates already played parts when scrubbing backwards.
3. ✅ **Done.** manual seeking leaves loop mode, i don't think so
   → Seeking no longer leaves loop mode; while a loop is armed, scrubbing stays in the loop.
4. ✅ **Done.** scrolling out of a loop while a loop is activated should have the same behavior as going out of bounds (reference to 1 & 3)
   → Already covered: while a loop is armed a scrub is a no-op and the release eases back to the loop (same "keep playing + snap back" as out-of-bounds).
5. ✅ **Resolved by the new design.** weird shadows/gleam on the outlines of every item
6. ✅ **Done.** is there something like prettier in swift? because the formatter seems to just not format everything correctly (or you as AI have a different codestyle)
   → Yes — **SwiftFormat** (config at `looped/.swiftformat`; Apple also ships `swift-format`). It was missing a `--swiftversion`, which silently disables rules and prints a warning; added `--swiftversion 5.0` so formatting is now consistent/deterministic.
7. pitch doesnt work with currentTime and the way the waveform scrolls through. this is definitely an issue as the loop points don't work as they should then
8. UI: Pitch and Volume need to have an Indicator when sliding. That means, when i slide to a different value, i want the headline of the slider (e.g. "Pitch" or "Volume") to be the current Value of the slider, trimmed to a human understandable and helpful value.
