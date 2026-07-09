# 05 — End-of-track playthrough modes

Depends on: **01 (track library)** and **03 (transport/auto-advance)** for *track-advance
mode*. Loop mode and stop mode have no dependencies — if this ships before 01/03,
implement those two and leave advance mode greyed out / skipped in the cycle.

## What

A user rehearsing wants to choose what happens when the current track reaches its end.
Three modes:

- **Loop mode** — the track restarts from the beginning and keeps playing.
  (Whole-track repeat; independent of the A/B loop-point feature, which already loops
  a region while armed.)
- **Track-advance mode** — the next track from the library starts playing (this is the
  auto-advance behavior from plan 03, made one mode of three).
- **Stop mode** — playback pauses and the playhead resets to the start, exactly like
  clicking the stop button.

## The mode button

- **One button** cycles through the three modes on click; its icon changes per mode
  (SF Symbols, e.g. `repeat` / `text.line.first.and.arrowtriangle.forward` / `stop`).
- **Hover** shows a native tooltip (`.help(...)`) explaining the current mode, e.g.
  "Loop: restart this track when it ends".
- **Placement: sidebar for now.** Plan 07 (controls redesign) later *moves* this button
  into the bottom-bar transport cluster — build it as a small reusable view (e.g.
  `PlaythroughModeButton`) so relocation is trivial.

## Implementation notes

- Model: `enum PlaythroughMode: CaseIterable { case loop, advance, stop }`, a
  `@Published var playthroughMode` on `PlayerViewModel` (persisting it via `@AppStorage`
  is fine — decide in implementation, note it in CLAUDE.md).
- End-of-track detection: hook wherever plan 03 detects track end (completion callback /
  clock reaching duration) and branch on the mode. While an A/B loop is armed the track
  never "ends", so the mode only fires in normal playback.
- Keep the branching logic in `PlayerViewModel` (intent layer), not in views or
  `PlaybackService`.

## Tests

- `PlayerViewModelTests`: for each mode, simulate end-of-track against
  `FakePlaybackService` and assert restart / advance-call / stop respectively; assert
  the cycling order of the mode setter.
