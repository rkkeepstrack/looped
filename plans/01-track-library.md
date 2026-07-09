# 01 — Track model, library, click-to-play

**Scope:** the library core: `Track` model, `LibraryViewModel`, sidebar track list,
click a row → loads + plays, multi-select open panel. No drag & drop (02), no
next/prev (03), no persistence (06).

## Current state (anchors)

- Sidebar shell exists: `ContentView.swift` → private `Sidebar` ("Your tracks will
  appear here" placeholder + Import button calling `PlayerViewModel.openFile()`).
- Single-file open panel: `PlayerViewModel.openFile()` (`allowsMultipleSelection = false`),
  then `load(url:)` → `apply(_:)` (which already resets loop points + transport on
  track change — reuse as-is).
- Composition root: `loopedApp.swift` builds services + the two view-models.
- Mock: `plans/mockup/2026-07-08-ui-layout.png` — plain filename list, current track
  orange, under the Import button.

## Design

- `Models/Track.swift` — value type: `id: UUID`, `url: URL`, `title: String`,
  `duration: TimeInterval?`. `Identifiable`, `Equatable`.
- `ViewModels/LibraryViewModel.swift` — `ObservableObject`:
  - `@Published private(set) var tracks: [Track]`, `@Published var currentTrackID: UUID?`.
  - `add(urls: [URL]) async` — dedupe by `url.standardizedFileURL`, filter to
    wav/mp3/aiff (`UTType(filenameExtension:)?.conforms(to: .audio)`), read title +
    duration, append. This is the single intake path 02 reuses.
  - `play(_ track: Track) async` — delegates to `PlayerViewModel.load(url:)` then
    starts playback; sets `currentTrackID`.
  - Constructor-injected reference to `PlayerViewModel` (wired in `loopedApp`;
    view-model → view-model is acceptable here — it's the bridge, services stay clean).
- Sidebar list: replace the placeholder `Text` with a `ScrollView`/`LazyVStack` (or
  `List` restyled — `List` fights `Theme.surface` backgrounds on macOS, prefer the
  simple stack) of rows: title, small duration; current row `Theme.accent`; row tap
  → `library.play(track)`.
- Open panel: `allowsMultipleSelection = true`; selected URLs → `library.add(urls:)`;
  if the library was empty, auto-play the first added track. `openFile()` moves to
  `LibraryViewModel` (the panel is import-UI, not playback).

## Technical notes (researched)

- **Metadata:** don't decode the whole file for the list. Use
  `AVURLAsset(url:)` + `try await asset.load(.duration)`; title from
  `asset.load(.commonMetadata)` first `AVMetadataItem` with `commonKey == .title`
  (`try await item.load(.stringValue)`), falling back to
  `url.deletingPathExtension().lastPathComponent`. All async — run in `add(urls:)`
  off the main actor, publish on main.
- **Playing a track still goes through `AudioFileService.load`** (full decode into
  the loop buffer) — the 20-min limit + `loadError` path applies per play, not per add.
- The app is **not sandboxed** (SwiftPM bundle, no entitlements — see 06), so URLs
  stay readable; no security-scope dance on open-panel URLs.

## Steps

1. `Track` + `LibraryViewModel` (+ protocol only if a service emerges; the VM calling
   `AVURLAsset` directly is fine — wrap metadata in a tiny `TrackMetadataService` if
   tests need it faked).
2. Move/upgrade the open panel to multi-select in `LibraryViewModel`.
3. Sidebar list UI + row tap → play, current-track highlight.
4. Wire in `loopedApp` (`@StateObject`, `environmentObject`).
5. Tests: `LibraryViewModelTests` — add/dedupe/filter (use `AudioFixture` temp WAVs),
   `play` sets `currentTrackID` and drives a spy player. Extend `TestDoubles` as needed.
6. Update `CLAUDE.md` (architecture, file map) + `plans/README.md`.

## Acceptance

- [ ] Import panel accepts multiple files; they appear as sidebar rows (title + duration).
- [ ] Clicking a row loads and plays it; the row highlights orange; loop points reset.
- [ ] Duplicate/unsupported files are skipped silently.
- [ ] Unit tests for add/dedupe/filter/play.
