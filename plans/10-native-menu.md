# 10 — Native menu bar overhaul: File → Library, full Playback, new Loop menu

**Depends on:** the shipped menu bar (plan 07, `AppCommands` in `loopedApp.swift`).
Delete-highlighted-entry additionally depends on **plan 08's** selection lift + delete
intent (`LibraryViewModel.remove`, published `selectedTrackID`) — implement that part
after or alongside 08.
**Scope:** replace the leftover default menus with app-shaped ones: a Library-flavored
File menu (import files / import folder / remove selected), a complete Playback menu
(transport + rate/pitch/volume/sync with shortcuts), and a new Loop menu for the A/B
points. Remove the useless Edit menu.

## Current state (anchors)

- `AppCommands` (`loopedApp.swift`, `Commands` struct with `@ObservedObject` view-models
  so titles/enablement stay live): `CommandGroup(replacing: .newItem)` → "Open…" (⌘O →
  `LibraryViewModel.openFilesAndLoad`), plus a `CommandMenu("Playback")` with
  Play/Pause, Stop, and the playthrough-mode Picker. Nothing else is customized, so
  SwiftUI leaves the **default Edit menu** (Undo/Cut/Copy/Paste — nothing in the app
  uses the responder chain, all items are permanently dead) and the default File
  residue (Close ⌘W etc.).
- Intents already exist for almost everything: `LibraryViewModel.openFiles()` /
  `openFolder()` / `openFilesAndLoad()` / `next()` / `previous()`;
  `PlayerViewModel.play()` / `pause()` / `togglePlayPause()` / `stop()` /
  `toggleLoopStart()` / `toggleLoopEnd()` / `clearLoopPoints()` / `nudgeLoopStart/End` /
  `updateSync(_:)` / `playthroughMode`. Volume/rate are `@Published` values the sliders
  bind to (`volume` 0…2, `rate` 0.5…2 log-mapped, `pitchSemitones` −12…+12).
- Bare-key shortcuts (space, tab, a/b/r) are handled by the **local key monitor**
  (`Views/Modifiers/KeyboardShortcuts.swift`), *not* by menu items.

## Design

### 1. File menu → library actions

Replace the whole new/open/save group (`CommandGroup(replacing: .newItem)`, plus
`.saveItem` and `.importExport` if present) with:

- **Import Files…** ⌘O → `openFilesAndLoad` (keep plan 07's behavior: add all, load
  the first chosen).
- **Import Folder…** ⇧⌘O → `openFolder`.
- **Remove Selected Track** ⌘⌫ → the plan-08 delete intent; disabled while nothing is
  selected. If 10 ships before 08, leave this item out rather than stubbing it.
- Keep the system Close/Quit items (⌘W closing the window is standard macOS; don't
  fight it).

### 2. Remove the Edit menu

`CommandGroup(replacing: .undoRedo) {}` + `CommandGroup(replacing: .pasteboard) {}`
empties it; SwiftUI hides an empty Edit menu entirely. If a future plan adds text
fields (e.g. search), this decision gets revisited — note it in the plan when it does.

### 3. Playback menu — complete transport + parameters

Transport section (existing intents, now with shortcuts):

- **Play/Pause** (live title) — space is already the monitor's job; give the menu item
  no `keyboardShortcut` and *don't* try to render a bare-space equivalent (see
  "Shortcuts policy" below).
- **Stop** ⌘. (the conventional "interrupt").
- **Next Track** ⌘→, **Previous Track** ⌘← → `library.next()`/`previous()`; disabled
  with < 2 tracks (mirror the buttons' rule).
- The existing **When a Track Ends** Picker stays.

Parameters section (menu = discoverability + keyboard nudges, sliders stay the
primary control):

- **Volume Up / Down** ⌘↑ / ⌘↓ — step `volume` by 0.1, clamped to 0…2, then
  `updateVolume()`.
- **Faster / Slower** ⌘+ / ⌘− — step `rate` in the slider's log space (e.g. 1/12 of
  the 0…1 position ≈ one semitone-ish step), then `updateRate()`.
- **Pitch Up / Down** ⌥⌘+ / ⌥⌘− — ±1 semitone, then `updatePitch()`; disabled while
  synced (the pitch slider is hidden in that mode — the menu must match).
- **Reset Speed & Pitch** — rate 1×, pitch 0 st (the sliders' right-click reset,
  discoverable).
- **Sync Pitch & Rate** ⌥⌘S — checkmark toggle (`Toggle`/checked `Button`) →
  `updateSync(!syncPitchAndRate)`.

All playback items disabled while `audioURL == nil` (as Play/Stop already are).

### 4. New Loop menu

- **Set/Clear Loop Start** (live title: "Set Loop Start at Playhead" vs "Clear Loop
  Start") → `toggleLoopStart()`; same for **Loop End** → `toggleLoopEnd()`.
- **Clear Loop Points** → `clearLoopPoints()`; disabled while neither point is set.
- **Nudge** section: Start/End Earlier/Later (±0.05 s, the panel's chevron step) →
  `nudgeLoopStart/End`; disabled while the respective point is unset.
- Shortcuts: a/b/r stay with the key monitor (bare keys). Menu items get either no
  equivalent or modifier variants (⌥A / ⌥B / ⌥R) — decide at implementation time,
  but **never** double-bind the same key in both places.

### 5. Shortcuts policy (the gotcha to write down)

Two dispatch paths exist: the **local key monitor** (bare keys: space, tab, a/b/r —
swallowed before the menu system sees them) and **menu `keyboardShortcut`s**
(modifier-based). Keep them disjoint: bare keys belong to the monitor (menu items show
no equivalent for them), modifier combos belong to menus (the monitor already ignores
⌘/⌥/⌃ events). A key bound in both places would fire twice or shadow unpredictably.
Document the split in CLAUDE.md's gotchas.

## Non-goals

- No menu-driven track list (a Window/tracks submenu) — the sidebar is the list UI.
- No user-configurable shortcuts.
- No Edit-menu resurrection for hypothetical future text fields.

## Tests

Menu enablement/titles are thin projections of already-tested VM state, and `Commands`
bodies aren't unit-testable headlessly — cover the *new intents only*:

- `PlayerViewModelTests`: volume/rate/pitch step intents (clamping at 0/2, 0.5×/2×,
  ±12 st; pitch step refused while synced), reset-speed-and-pitch pushes rate 1 /
  pitch 0 to the engine (via `FakePlaybackService`).
- Loop nudge/toggle intents are already covered (plan 07 + earlier).
- The menus themselves: manual QA checklist in `TESTING.md` (every item fires, titles
  flip live, disabled states track selection/load/sync state, no double-fire with the
  key monitor).
