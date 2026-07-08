# Plan 5 — Player features: library, click-to-play, drag & drop

**Type:** Feature
**Depends on:** Plan 4 (needs a `Track` model + `LibraryViewModel`). Best done
after the architecture split, or bundled with it.
**Primary files:** new `Models/Track.swift`, new `ViewModels/LibraryViewModel.swift`,
new `Views/LibraryView.swift`, plus `ContentView`, `loopedApp`, and audio layer.

## Problem

Today the app loads **one** file at a time via an `NSOpenPanel`
(`AudioEngineController.openFile()`, `AudioEngineController.swift:62-71`) and has no
concept of a library. It should behave like a normal player: load in songs, see
them listed, **click a song to play it**, and **drag & drop** files/folders in
easily.

## Goal / desired behavior

1. A **library/playlist** of loaded tracks, shown in the sidebar list (the
   collapsible sidebar shell itself ships in Plan 3; this plan fills it with the
   track list + import).
2. **Click a track → it loads and plays.** Current track highlighted (orange).
3. **Drag & drop** audio files (and folders of audio) onto the window to add them;
   also multi-select in the open panel.
4. Basic transport across the library: next/previous, optional auto-advance.
5. (Stretch) **persist** the library across launches.
6. **Loop-point nudge** (from the Plan 3 mock): the Loop panel shows `<< A >>` and
   `<< B >>` — the `<<`/`>>` buttons fine-adjust each loop point left/right by a
   small increment (e.g. ±0.05–0.1 s, or a modifier for finer/coarser), re-arming
   the loop. Plan 3 builds the Loop panel + A/B/Reset; **this plan wires the nudge
   arrows** (buttons + `nudgeLoopStart/End(by:)` on `PlayerViewModel`, clamped so
   A < B and within [0, duration]).
7. **Independent pitch + rate, with a sync toggle** (upgrade of the single Plan 3
   slider). Two sliders — **Rate** (tempo) and **Pitch** (semitones) — driving
   `AVAudioUnitTimePitch.rate` and `.pitch` separately, plus a **sync knob/toggle**
   that links them so one slider drives both together (i.e. plain varispeed:
   speed+pitch move as one). Rationale: *independent* is for rehearsing melodic
   instruments (slow down without transposing, or transpose without slowing);
   *synced* is highest audio quality (no time-stretching artifacts) — good for
   drummers who only need tempo. When synced, one slider maps to a rate change and a
   matching pitch shift (`pitch = 1200 * log2(rate)` cents) so it sounds like tape
   speed. Plan 3 ships a single rate slider labeled "Pitch"; this replaces it.
8. **Smooth (display-synced) waveform pan** — worth investigating. Playback position
   is currently polled by a 0.03 s `Timer` (~33 Hz) in `PlayerViewModel`, so the
   waveform's offset advances in discrete steps that don't line up with the display
   refresh (60/120 Hz) → the scroll looks slightly steppy/rough even in a Release
   build. Drive the pan off the display refresh instead: interpolate `currentTime`
   between engine samples each frame via SwiftUI `TimelineView(.animation)` (or a
   `CADisplayLink`), keeping the 0.03 s engine poll only as the source of truth.
   Independent of Debug-vs-Release (Release helps the CPU cost, not the stepping).

## Approach

### Model + state (Plan 4 alignment)

- `Track` (value type): `id`, `url`, `title` (from filename/metadata), `duration`,
  optional artwork/artist via `AVAsset` metadata.
- `LibraryViewModel : ObservableObject`: `@Published tracks: [Track]`,
  `selection`, `add(urls:)` (dedupe, filter by UTType), `remove`, `play(track:)`,
  `next()/previous()`. Bridges to `PlayerViewModel`/`AudioEngine` to actually play.

### UI

- `LibraryView`: a `List`/`Table` of tracks (title, duration), selectable; row tap
  or double-click → `library.play(track:)`. Themed per Plan 3.
- Layout: sidebar list + main waveform/controls (e.g. `NavigationSplitView` or an
  `HSplitView`), or a list panel above/below the waveform — pick per the mock.
- Empty state: a drop-target prompt ("Drop audio files here").

### Drag & drop (sandbox-aware)

- Attach `.onDrop(of: [.audio, .fileURL], isTargeted:)` to the window/root or the
  library panel; resolve `NSItemProvider` → file `URL`s; expand dropped folders;
  filter to WAV/MP3/AIFF (+ maybe m4a); call `library.add(urls:)`.
- **Sandbox:** app is sandboxed with `ENABLE_USER_SELECTED_FILES = readonly`.
  Drops and open-panel picks are user-initiated, so **read access is granted**.
- **Persistence (stretch):** to reopen tracks next launch, store **security-scoped
  bookmarks** (`url.bookmarkData(options: .withSecurityScope)`), and
  `startAccessingSecurityScopedResource()` on resolve. This needs the app-scope
  bookmark entitlement enabled in build settings — confirm before building persistence.

### Multi-file open panel

- Change `openFile()` to `allowsMultipleSelection = true` and route selected URLs
  into `library.add(urls:)` instead of loading a single file directly.

## Step-by-step

1. Add `Track` model + metadata extraction (`AVAsset` title/duration; reuse the
   `loadDuration` pattern from `AudioEngineController.swift:242-251`).
2. Add `LibraryViewModel` (add/remove/dedupe/select/play/next/prev).
3. Wire library → player: `play(track:)` calls into the audio layer's `load` +
   play; update "now playing" state.
4. Build `LibraryView` (themed list, selection, tap-to-play, empty/drop state).
5. Integrate into `ContentView` layout (split view or panel).
6. Implement `.onDrop` intake (files + folders, filtered) → `add(urls:)`.
7. Switch the open panel to multi-select feeding the same intake path.
8. Add next/previous controls (+ optional auto-advance on track end — hook into the
   existing end-of-file detection, `reachedEndOfFile()`).
9. **Loop nudge:** add `nudgeLoopStart(by:)` / `nudgeLoopEnd(by:)` to
   `PlayerViewModel` (clamp A < B, [0, duration], then `refreshLoop()` to re-arm),
   and wire the `<<`/`>>` buttons in the Plan 3 Loop panel to them.
10. **Pitch + rate + sync:** expose `pitch` (cents/semitones) on `PlayerViewModel`
    → `PlaybackService.setPitch`; add a `syncPitchAndRate` toggle; second slider in
    the bottom-left wrapper; when synced, one slider sets both (`pitch = 1200 *
    log2(rate)`). Re-slicing the loop buffer isn't needed (pitch/rate are live on
    the timePitch unit), but re-verify the loop seam/clock at extreme settings.
11. **Smooth pan:** wrap the waveform pan in `TimelineView(.animation)` (or a
    `CADisplayLink`); interpolate `currentTime` from the last engine sample +
    elapsed × rate each frame, so the offset updates per display frame instead of
    per 0.03 s tick. Keep the timer as the authoritative position.
12. (Stretch) security-scoped bookmarks for persistence; enable the entitlement.
13. Update `CLAUDE.md` (file map, architecture, features).

## Files touched

- **New:** `Models/Track.swift`, `ViewModels/LibraryViewModel.swift`,
  `Views/LibraryView.swift`.
- `looped/Views/ContentView.swift` (layout + drop target),
  `looped/loopedApp.swift` (inject `LibraryViewModel`), audio layer (`load`/play
  entry points), possibly `ControlsView` (next/prev).
- Build settings/entitlements **only if** doing persistence (bookmark entitlement).
- `CLAUDE.md`.

## Risks & considerations

- **Sandbox persistence** is the main gotcha — plain stored URLs won't reopen after
  relaunch; bookmarks + entitlement are required. Keep persistence as a clearly
  separable stretch step so the core feature ships without it.
- **Folder drops** can be large — expand asynchronously; don't block the UI while
  extracting metadata for many files (do it lazily / off the main actor).
- **Playback interruption:** clicking a new track mid-playback must cleanly stop and
  reschedule (interacts with loop state from Plan 2 — clear the loop on track change).
- **Supported types:** currently WAV/MP3/AIFF; decide whether to add m4a/AAC/FLAC.
- **Metadata cost:** extracting title/artwork for every dropped file has a cost;
  cache and load lazily.

## Acceptance criteria

- [ ] Dropping audio files (and folders) onto the window adds them to the library.
- [ ] Library lists tracks with title + duration; current track is highlighted.
- [ ] Clicking/double-clicking a track loads and plays it.
- [ ] Open panel supports multiple selection into the same library.
- [ ] Next/previous work; (optional) auto-advance at track end.
- [ ] Loop `<<`/`>>` nudge arrows shift A/B by a small step and re-arm the loop,
      clamped so A < B within [0, duration].
- [ ] Independent Rate + Pitch sliders; a sync toggle links them (one slider =
      varispeed, speed+pitch together) for artifact-free quality.
- [ ] Waveform pan is smooth/display-synced (no visible 33 Hz stepping), position
      still driven by the engine.
- [ ] (Stretch) library reopens after relaunch via security-scoped bookmarks.

## Open questions

- **Mock design** for the library/layout (promised) — drives list vs sidebar, and
  where the waveform/controls sit.
- Persist the library across launches now, or later?
- Auto-advance to next track on end — on by default?
- Which extra formats (m4a/AAC/FLAC) to support?
