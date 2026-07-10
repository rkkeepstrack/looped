# `looped` — plans

Remaining work only. Completed plans were removed once shipped (see git history).
Build/run/test and architecture live in the repo-root `CLAUDE.md`.

Ordered, reviewable slices:

- **[08-library-qol.md](08-library-qol.md)** — library QoL: ⌫/⌦ delete, drop below the
  list appends, animated drop hint while dragging. ⬜ (independent)
- **[09-error-toasts.md](09-error-toasts.md)** — general error handling: themed toasts,
  meaningful messages, per-action aggregation, no silent failures. ⬜ (best last-ish —
  touches most layers)
- **[10-native-menu.md](10-native-menu.md)** — menu bar overhaul: File → library actions
  (import files/folder, remove selected), full Playback menu with shortcuts +
  rate/pitch/volume/sync, new Loop menu, Edit menu removed. ⬜ (remove-selected part
  depends on 08)
- **[bug-fixes.md](bug-fixes.md)** — open bugs. Currently empty.

**Mockups:** `mockup/2026-07-08-ui-layout.png` (sidebar list, controls layout),
`mockup/ui-small-waveform-view.png` (full-track preview strip).

**Done & shipped** (plan files removed): waveform striped rendering · seamless A/B loop
points · UI redesign · service-oriented architecture split · windowed waveform
rendering · display-synced smooth pan + wall-clock playback clock · scrub
highlight/anchor · rate-desync fix · live slider labels · independent rate+pitch with
varispeed sync toggle · loop-point nudge arrows · track library (01: `Track` +
`LibraryViewModel`, sidebar list, click-to-play, multi-select import) · drag & drop
import (02: whole-window drop of files/folders, recursive expansion, targeted highlight) ·
library transport (03: next/previous buttons, auto-advance at track end,
`PlaybackCoordinator` store replacing the VM→VM bridge) · full-track preview strip
(04: whole-song minimap under the waveform — box mirrors the viewport, box-drag
scrubs and seeks on release, click seeks) · playthrough modes (05: loop / advance /
stop at end of track, one cycling sidebar button, branch in `PlayerViewModel`) ·
library persistence (06: JSON `LibraryStore` — list, selection, per-track slider
values — restored on launch; playthrough mode in `UserDefaults`) · controls redesign
(07: slim bottom bar with viewport-centered split play/pause + mode transport, sync-link
icon, sidebar import-folder button, native menu bar with File ▸ Open… ⌘O + Playback menu).
