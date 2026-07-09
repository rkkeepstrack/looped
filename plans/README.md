# `looped` — plans

Remaining work only. Completed plans were removed once shipped (see git history).
Build/run/test and architecture live in the repo-root `CLAUDE.md`.

The old monolithic player-features plan is split into reviewable slices, ordered;
01→02→03 build on each other, 04 is independent, 06 is a stretch:

- **[01-track-library.md](01-track-library.md)** — `Track` model, `LibraryViewModel`,
  sidebar track list, click-to-play, multi-select open panel. ⬜
- **[02-import-drag-drop.md](02-import-drag-drop.md)** — drop files/folders onto the
  window → library intake. ⬜ (needs 01)
- **[03-transport-auto-advance.md](03-transport-auto-advance.md)** — next/previous +
  auto-advance at track end. ⬜ (needs 01)
- **[04-loop-nudge.md](04-loop-nudge.md)** — wire the `«`/`»` loop-point nudge arrows. ⬜
- **[06-library-persistence.md](06-library-persistence.md)** — persist the library
  across launches (stretch; the app is unsandboxed, plain paths suffice). ⬜
- **[bug-fixes.md](bug-fixes.md)** — open bugs. Currently empty.

**Mockup:** `mockup/2026-07-08-ui-layout.png` (sidebar list, controls layout).

**Done & shipped** (plan files removed): waveform striped rendering · seamless A/B loop
points · UI redesign · service-oriented architecture split · windowed waveform
rendering · display-synced smooth pan + wall-clock playback clock · scrub
highlight/anchor · rate-desync fix · live slider labels · independent rate+pitch with
varispeed sync toggle.
