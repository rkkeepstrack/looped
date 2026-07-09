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

## Architecture note — revisit the VM→VM coupling here

`LibraryViewModel` currently holds a direct `PlayerViewModel` reference (documented
smell; it's the library↔playback bridge). This plan adds the *reverse* arrow too
(`onTrackEnded` → library picks the next track), making the coupling bidirectional —
the natural moment to fix it rather than pile on. Options (discussed 2026-07-09):

1. **Minimal:** replace the stored `PlayerViewModel` with an injected closure
   (`playTrack: (URL) async -> Bool`, returning load success so the library knows
   whether to move `currentTrackID`), wired in `loopedApp` — mirroring how
   `onTrackEnded` is wired in the other direction. Do at least this.
2. **Cleaner (prefer if the wiring gets hairy):** extract a UI-free
   playback-coordination store owning "current source + transport" state; both
   view-models depend on it, `PlayerViewModel` becomes a thin projection, and
   `apply(_:)`'s track-change reset choreography moves into it.

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
