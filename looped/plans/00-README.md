# `looped` — Improvement Plans

Five tracked problems, one plan file each. Each plan is self-contained: problem →
root cause (with `file:line` refs) → goal → step-by-step → files touched → risks →
acceptance criteria → open questions.

| # | Plan | Type | Blocks / depends on |
|---|------|------|---------------------|
| 1 | [Waveform rendering](01-waveform-rendering.md) | Bug + feature | Lightly depends on (4) |
| 2 | [Loop points](02-loop-points.md) | Bug | Independent |
| 3 | [UI redesign](03-ui-redesign.md) | Polish | Best after (4) |
| 4 | [Architecture](04-architecture.md) | Refactor / **decision doc** | Foundation for 1,3,5 |
| 5 | [Player features](05-player-features.md) | Feature | Depends on (4) |

## Recommended sequencing

1. **Plan 4 first, but only the decisions** — agree the target module boundaries
   (`AudioEngine` vs `PlayerViewModel` vs presentation helpers). This is a
   "let's decide together" doc; nothing else should harden the current structure
   until we pick a direction.
2. **Plan 2 (loop points)** — self-contained functional bug, high value, no UI
   dependency. Fixes a real freeze (`checkLoop()` busy-waits on the main thread).
3. **Plan 1 (waveform)** — restore rendering + SoundCloud striped look. Small
   dependency on the naming settled in (4).
4. **Plan 3 (UI redesign)** — orange/black theme, compact sliders. Cleanest once
   (4) has separated view-models from views.
5. **Plan 5 (player features)** — library, click-to-play, drag & drop. Needs the
   `Track`/library model introduced by (4).

## Environment notes (verified 2026-07-07)

- App is **sandboxed** (`ENABLE_APP_SANDBOX = YES`) with
  `ENABLE_USER_SELECTED_FILES = readonly`. Drag-and-drop of files counts as a
  user selection, so read access is granted; **persisting** a library across
  launches needs security-scoped bookmarks (see Plan 5).
- Deployment target **macOS 15.6**, Swift language mode **5.0**.
- CLI `xcodebuild` is unavailable in the agent environment (`xcode-select` points
  at CommandLineTools). Build/verify in Xcode (⌘R), or run
  `sudo xcode-select -s /Applications/Xcode.app` to enable CLI builds.
- A `Stop` hook (`.claude/hooks/check-claude-md.sh`) blocks turns that change
  Swift without a *relevant* `CLAUDE.md` update — keep docs in sync per plan.
