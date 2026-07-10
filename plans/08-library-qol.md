# 08 — Library QoL: delete, forgiving drops, drop hint

**Depends on:** nothing beyond the shipped library chain (01–03).
**Scope:** three small library quality-of-life features: delete-key removal,
drop-anywhere-below appends to the end, an animated drop hint while dragging.

## Current state (anchors)

- Selection is view-local: `TrackListView.selectedTrackID` (`@State`, visual only);
  `LibraryViewModel.currentTrackID` marks the *loaded* track. There is no delete path
  in `LibraryViewModel` at all (only `add`/`move`).
- Key handling: `Utils/KeyboardHandler.swift` (`NSViewRepresentable` local key
  monitor; currently spacebar → play/pause). The hand-rolled list has **no keyboard
  navigation** (documented cost) — delete acts on the clicked selection, not a focus ring.
- Library drops land on `TrackListView`'s content `VStack` via `TrackListDropDelegate`;
  `RowInsertion.gapIndex(y:rowHeight:count:)` maps the pointer to an insertion gap and
  the hairline `insertionLine` renders it. The content has a 2-row clear tail, but the
  scroll area *below* that tail isn't a drop target.
- Empty-library drop zone ("drop audio files or folders here") lives in
  `SidebarView` as the empty state — it disappears once tracks exist.

## Design

### 1. Delete from the library (⌫ / ⌦)

- `LibraryViewModel.remove(_ track: Track)` (or by ID): drops the row. Removing the
  **current** track *unloads* it: playback stops, the source is cleared, and the
  content view shows an empty state. Needs a new `PlaybackCoordinator.unload()`
  (stop + drop `loaded`/`currentURL`/`duration`; fires `onSourceChanged` so loop
  points clear) — today there is no unload path, a source only gets *replaced*.
- **Empty content view**: with no track loaded, the waveform area shows a small
  centered placeholder mockup (app name / simple mark + a "load a track" hint —
  a real logo may replace the mark later, keep it swappable). This state also
  covers first launch before anything is imported.
- Key plumbing: extend `KeyboardHandler` to report delete/forward-delete, gated the
  same way spacebar is (don't steal keys from text fields). It needs the *selected*
  track — lift `selectedTrackID` out of `TrackListView` into `LibraryViewModel`
  (published selection intent; still "visual only" for playback). Selection moves to
  the neighbor after deleting so repeated ⌫ works.

### 2. Drop below the list appends

- Make the whole library column below the rows a drop target (today: rows + 2-row
  tail only). Simplest shape: give the ScrollView's remaining space to the existing
  delegate and clamp `RowInsertion.gapIndex` results past the last row to
  `count` (append). The insertion line still shows at the last gap so the feedback
  matches the outcome.
- Watch the coordinate-space gotcha that put the delegate on the *content* view in
  the first place: drop coordinates must survive scrolling. Either keep one delegate
  and extend the content to fill the viewport height, or add a second delegate on the
  empty area that hard-codes `gapIndex = count`.

### 3. Drop hint while dragging

- While a **drag hovers the library** and there is free vertical space below the
  rows, show a "Drop audio files or folders here" field (reuse the empty-state
  styling from `SidebarView`) in that free space; hide it when the tracks fill the
  visible column (no free space → no field, the insertion line alone carries the
  feedback).
- Appear on drag-enter, disappear on drop/exit — **small linear animation**
  (`.animation(.linear(duration: ~0.15))` on opacity; no spring, no scale).
- Drive it from the drop delegate's enter/exit (`ReorderState.externalGapIndex`
  already tracks external-drag hover — a `isExternalDragHovering` flag next to it
  fits; keep the gap math in `RowInsertion`).

## Steps

1. `PlaybackCoordinator.unload()` + `LibraryViewModel.remove` + selection lift +
   tests (remove current unloads/stops, neighbor selection, empty library no-op).
1a. Empty-state placeholder in the content view (shown whenever nothing is loaded).
2. `KeyboardHandler` delete keys → remove; manual QA note in `TESTING.md`
   (key events need a window).
3. Below-list drop target + `RowInsertion` clamp + tests (gap past the tail → count).
4. Drop-hint field + linear fade; visibility rule (free space only) + `ReorderState`
   flag tests.
5. `CLAUDE.md` + `plans/README.md`.

## Acceptance

- [ ] ⌫/⌦ removes the selected track; selection moves to a neighbor.
- [ ] Removing the currently loaded track stops playback, unloads it, and the content
      view shows the empty-state placeholder (same one as before any track is loaded).
- [ ] Dropping anywhere in the empty lower section of the library appends to the end,
      with the insertion line shown at the last gap.
- [ ] During an external drag over the library, the drop-hint field fades in (linear)
      in the free space — and never appears when the list fills the column; it fades
      out on drop or drag-exit.
