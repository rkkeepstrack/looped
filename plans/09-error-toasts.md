# 09 — Error handling: toast messages

**Depends on:** nothing (touches most layers, so best after the in-flight library work
settles).
**Scope:** a general error-surfacing story: themed toast notifications, meaningful
per-cause messages, errors aggregated per action — and no more silently swallowed
failures (`@discardableResult`, silent skips, `print`).

## Current state (anchors)

- The only user-visible error is `PlaybackCoordinator.loadError` (a `String?`), shown
  as text in the header (`ContentView`); it covers decode failures and the 20-min
  limit (`AudioFileServiceError.tooLong`).
- Silently swallowed today: unsupported/duplicate files in `LibraryViewModel.add`
  (deliberate for dedupe, but a fully-rejected import gives zero feedback);
  drag & drop provider resolution failures (`DroppedFileService.urls(from:)` drops
  them); folder expansion yielding nothing; engine start failures
  (`AVPlaybackService` → `print`); `LibraryViewModel.load`'s success `Bool` is
  `@discardableResult` — several callers ignore it.

## Design

### Toast store + view

- **`Stores/ToastCenter`** — UI-free `ObservableObject` injected where errors arise
  (view-models + coordinator; services stay throwing, they don't know about toasts):
  `report(_ error: ...)` / `report(messages: [String])`, published queue of toasts,
  auto-dismiss after ~4 s (timer), manual dismiss on click. New toasts while one is
  visible stack (queue), they don't replace.
- **`Views/ToastView`** — themed card (Theme tokens, no system accent), bottom-trailing
  overlay above the controls bar in `ContentView`; shows the message list of one toast
  (multi-line when aggregated), fades/slides in and out.

### Meaningful messages

- One `LocalizedError` per cause, not generic strings: file too long (exists), decode
  failed (with filename), unsupported type (with filename + extension), nothing usable
  in a dropped folder, engine failed to start. Message text names the *file* and the
  *reason* — "3 files skipped: not audio (`notes.txt`, `cover.jpg`) …", not
  "import failed".
- Dedupe skips stay **silent** (re-adding an existing track is a no-op by design, not
  an error) — decide per cause, not blanket-toast everything.

### Aggregation per action

- Errors from one user action (an import of N files, one drop, one load) collect into
  **one toast** with all messages, not N toasts. Shape: intake paths
  (`add`, `addDropped`, `loadDropped`) gather `[SkipReason]` while iterating and
  report once at the end.

### Kill the fire-and-forget results

- `LibraryViewModel.load` loses `@discardableResult`: callers either use the result
  (next/previous/auto-advance already do) or the failure surfaces as a toast — the
  header `loadError` text is **replaced** by the toast (single error channel; the
  header stays clean).
- `AVPlaybackService` engine-start failures propagate (throwing init/setSource or a
  reported error) instead of `print` — decide the mechanics in implementation; a
  broken engine must not fail invisibly.

## Steps

1. `ToastCenter` + `ToastView` + wiring in `loopedApp`/`ContentView`; migrate the
   existing `loadError` path to it (header text removed).
2. Error taxonomy: `LocalizedError` conformances with filenames in the messages;
   intake paths collect + aggregate per action; drop `@discardableResult`.
3. Engine-start failure surfacing.
4. Tests: `ToastCenter` queue/dismiss logic; intake aggregation (N bad files → one
   toast, message content); load-failure toast replaces `loadError` assertions.
5. `CLAUDE.md` (+ `TESTING.md`: toast look/timing is manual QA) + `plans/README.md`.

## Acceptance

- [ ] A failed load shows a toast naming the file and reason; the header no longer
      shows error text.
- [ ] Importing/dropping a mix of good and bad files adds the good ones and shows
      **one** toast listing every skipped file with its reason; duplicates stay silent.
- [ ] A drop that yields nothing usable (empty folder, all unsupported) says so.
- [ ] Toasts auto-dismiss (~4 s), can be clicked away, stack when several actions fail
      in a row; appearance/disappearance is animated.
- [ ] No `@discardableResult` error paths and no `print`-only failures remain.
