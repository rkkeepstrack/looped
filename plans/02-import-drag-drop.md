# 02 — Drag & drop import (files + folders)

**Depends on:** 01 (`LibraryViewModel.add(urls:)` is the intake).
**Scope:** drop audio files/folders anywhere on the window → added to the library.

## Design

- `.onDrop(of: [.fileURL], isTargeted: $isDropTargeted)` on `ContentView`'s root
  `HStack` (whole window is the target, per the old plan).
- Visual feedback while targeted: e.g. overlay border in `Theme.accent` (subtle),
  and the sidebar empty state doubles as "Drop audio files here".
- Resolve providers → URLs, expand folders, filter to audio, feed `add(urls:)`.

## Technical notes (researched)

- Provider → URL on macOS:
  `provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)` returns the URL
  as `Data`; reconstruct with `URL(dataRepresentation:relativeTo:)`. Wrap in a
  `withCheckedContinuation` helper; the `onDrop` closure must return `true`
  synchronously and kick a `Task` for the async work.
- Folder expansion: `FileManager.default.enumerator(at:includingPropertiesForKeys:
  [.isRegularFileKey])`, filter by `UTType(filenameExtension:)?.conforms(to: .audio)`
  intersected with the supported set (wav/mp3/aiff — same predicate as 01; keep it
  in one place, e.g. `Track.isSupported(url:)`).
- **Async + bounded:** folders can be huge — enumerate off the main actor; metadata
  extraction is already async per 01. No progress UI needed at this size; just don't
  block the drop callback.
- Not sandboxed → dropped URLs are directly readable, no security scope needed.

## Steps

1. Drop-URL resolution helper (provider → [URL]) + folder expansion in
   `LibraryViewModel` (pure enough to unit-test with a temp directory tree).
2. Attach `.onDrop` + targeted highlight in `ContentView`.
3. Tests: folder expansion + filtering over a fixture directory (nested folders,
   mixed extensions). Provider resolution stays a manual check.
4. `CLAUDE.md` (ContentView entry) + `plans/README.md`.

## Acceptance

- [ ] Dropping files adds exactly the supported ones; folders recurse.
- [ ] Drop-target highlight appears while dragging over the window.
- [ ] UI stays responsive during a large folder drop.
