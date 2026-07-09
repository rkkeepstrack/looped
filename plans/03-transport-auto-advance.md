# 03 — Next/previous + auto-advance

**Depends on:** 01.
**Scope:** library-order transport: next/previous controls, auto-advance at track end.

## Current state (anchors)

- End-of-track detection lives in `PlayerViewModel.startTimer()`:
  `if !playback.isLooping, currentTime >= duration { stop() }` — the auto-advance hook.
- Transport buttons: `ControlsView.transport` (play/pause + stop, centered).

## Design

- `LibraryViewModel.next()` / `previous()` — relative to `currentTrackID` in `tracks`
  order; clamp at the ends (no wrap; wrapping is a taste call — ask if wanted).
- `previous()` convention (standard player behavior): if > ~3 s into the track,
  restart the current track instead of going back.
- Auto-advance: `PlayerViewModel` exposes an `onTrackEnded: (() -> Void)?` callback
  (set by `LibraryViewModel` at wiring time); invoked where the timer currently
  calls `stop()`. Auto-advance ON by default (open question in the old plan —
  default on, it's a player).
- UI: `backward.fill` / `forward.fill` buttons flanking play/pause in
  `ControlsView.transport`; disabled when the library has < 2 tracks.
- A looping track never "ends" (fold in `currentTime()`) — auto-advance simply never
  fires while a loop is armed; that's correct, no special-casing.

## Steps

1. `next()/previous()` + tests (ordering, clamping, restart-on-previous rule).
2. `onTrackEnded` hook in `PlayerViewModel` timer + wiring in `loopedApp`; test via
   `FakePlaybackService` (drive `currentTime` past `duration`).
3. Buttons in `ControlsView`.
4. `CLAUDE.md` + `plans/README.md`.

## Acceptance

- [ ] Next/previous move through the library in list order; current row follows.
- [ ] Previous restarts the track when > 3 s in.
- [ ] Track end auto-plays the next track; last track just stops.
- [ ] Armed loop keeps looping (no auto-advance).
