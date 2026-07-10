# 06 — Library persistence (stretch)

**Depends on:** 01 (+ plays nicest after 02/03).
**Scope:** the library (track list + last selection) survives relaunch.

## Technical notes (researched)

- **The old plan's sandbox warning is stale.** The `just bundle` app has **no
  entitlements and no code signing** → not sandboxed → plain file paths remain
  readable across launches. Security-scoped bookmarks are unnecessary today.
  Leave a comment in the store: if the app is ever sandboxed/notarized for
  distribution, revisit with `url.bookmarkData(options: .withSecurityScope)` +
  the app-scope bookmark entitlement.
- Store: JSON via `Codable` at
  `FileManager.urls(for: .applicationSupportDirectory)[0]/looped/library.json`
  (create the dir; bundle id is `RK.looped` but a plain `looped` folder is fine).
  Persist `url` (as path), `title`, `duration`, plus `currentTrackID`.
- Load on launch: filter out paths that no longer exist (`FileManager.fileExists`);
  don't error, just drop them. Re-extracting metadata is unnecessary — it's persisted.
- Write: debounce-save on every library mutation (add/remove/reorder/selection);
  the list is tiny, a full rewrite per change is fine.

## Design

- `LibraryStore` protocol + `JSONLibraryStore` (Services/, pure: `load() -> [Track] +
  selection`, `save(...)`) — injected into `LibraryViewModel`, faked in tests.
- Don't auto-play on restore; just populate the list and highlight the last track.
- Also persist the **playthrough mode** (plan 05's `PlaythroughMode` on `PlayerViewModel`) —
  deliberately left session-only in 05 so all persistence lands here in one concept.
  A `UserDefaults` scalar is fine (it doesn't need the JSON store).

## Steps

1. `LibraryStore` + JSON impl + round-trip tests (temp dir).
2. Wire into `LibraryViewModel` (load in init/task, save on mutation).
3. Missing-file filtering test.
4. `CLAUDE.md` + `plans/README.md`.

## Acceptance

- [ ] Relaunch shows the same list + last current track (not playing).
- [ ] Tracks whose files were deleted vanish silently.
- [ ] Store is unit-tested; view-model uses it via protocol.
