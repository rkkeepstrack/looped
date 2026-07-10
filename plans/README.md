# `looped` — plans

Remaining work only. Completed plans were removed once shipped (see git history).
Build/run/test and architecture live in the repo-root `CLAUDE.md`.

Ordered, reviewable slices; 02→03 build on the shipped 01, 04 is independent,
05/07 build on the library+transport chain, 06 is a stretch:

- **[03-transport-auto-advance.md](03-transport-auto-advance.md)** — next/previous +
  auto-advance at track end. ⬜
- **[04-full-track-preview.md](04-full-track-preview.md)** — whole-song minimap below
  the waveform: highlight box mirrors the viewport, drag scrubs, click seeks. ⬜
  (independent)
- **[05-loop-end-modes.md](05-loop-end-modes.md)** — end-of-track playthrough modes
  (loop / advance / stop) behind one cycling icon button, sidebar-hosted for now. ⬜
  (advance mode needs 01+03)
- **[06-library-persistence.md](06-library-persistence.md)** — persist the library
  across launches (stretch; the app is unsandboxed, plain paths suffice). ⬜
- **[07-controls-redesign.md](07-controls-redesign.md)** — slim centered bottom bar:
  split play/pause + stop + mode + open toolbar, rate/pitch VStack with yellow sync-link
  icon, A/B marker labels, native menu bar. ⬜ (needs 01, 03, 05)
- **[bug-fixes.md](bug-fixes.md)** — open bugs. Currently empty.

**Mockups:** `mockup/2026-07-08-ui-layout.png` (sidebar list, controls layout),
`mockup/ui-small-waveform-view.png` (full-track preview strip).

**Done & shipped** (plan files removed): waveform striped rendering · seamless A/B loop
points · UI redesign · service-oriented architecture split · windowed waveform
rendering · display-synced smooth pan + wall-clock playback clock · scrub
highlight/anchor · rate-desync fix · live slider labels · independent rate+pitch with
varispeed sync toggle · loop-point nudge arrows · track library (01: `Track` +
`LibraryViewModel`, sidebar list, click-to-play, multi-select import) · drag & drop
import (02: whole-window drop of files/folders, recursive expansion, targeted highlight).
