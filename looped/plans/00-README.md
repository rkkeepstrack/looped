# `looped` — Improvement Plans

Five tracked problems, one plan file each. Each plan is self-contained: problem →
root cause (with `file:line` refs) → goal → step-by-step → files touched → risks →
acceptance criteria → open questions. **Each plan's top has a Status line — read it first.**

## Current status (2026-07-07) — START HERE

| # | Plan | Status |
|---|------|--------|
| 1 | [Waveform rendering](01-waveform-rendering.md) | ✅ **Done** (committed) |
| 2 | [Loop points](02-loop-points.md) | ✅ **Done** (committed) |
| 4 | [Architecture](04-architecture.md) | ✅ **Done — code, but NOT yet committed** (see below) |
| 3 | [UI redesign](03-ui-redesign.md) | ⬜ Not started — **suggested next** |
| 5 | [Player features](05-player-features.md) | ⬜ Not started |
| 6 | `06-bug-fixes.md` | ⚠️ The **user's own** file — do not touch/commit it |

**Immediate pending action:** the Plan 4 refactor (View → ViewModel → Service split)
is implemented and builds, but is **uncommitted** — the user is reviewing it first.
Once they approve, commit it (plus `plans/04-architecture.md`, the updated `00-README`,
and the new `.gitignore`). Do **not** commit `plans/06-bug-fixes.md` (user's) or
`xcuserdata`. The user commits directly to `main`; only commit when asked.

**Then:** Plan 3 (UI redesign) is the natural next step — the architecture is now in
place for it. Plan 5 (library / drag-drop) builds on `AudioFileService`.

## Recommended sequencing (original plan)

1. ✅ Plan 4 decisions → we went further and did the full split (service-oriented,
   DI'd — see plan 04's status header for the decisions taken).
2. ✅ Plan 2 (loop points) — seamless `.loops` looping, crossfade, pitch/format fix.
3. ✅ Plan 1 (waveform) — SoundCloud striped rendering, zoom, peak emphasis.
4. ⬜ **Plan 3 (UI redesign)** — orange/black theme (a minimal `Theme` already exists
   in `Views/Theme.swift`), compact sliders, custom controls.
5. ⬜ Plan 5 (player features) — library, click-to-play, drag & drop.

## Environment notes (verified 2026-07-07)

- **Building from the CLI** (system `xcode-select` points at CommandLineTools, so
  bare `xcodebuild` fails): prefix with the Xcode toolchain — no sudo needed:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -project looped.xcodeproj -scheme looped -configuration Debug build
  ```
  Run from the repo root (`looped/looped/`).
- **Xcode + externally-created files:** this project uses filesystem-synchronized
  groups, so new files are auto-included in builds — **but** if Xcode is open when a
  file is created by an external tool, Xcode may not notice it until you quit &
  reopen (symptom: "cannot find type X" for a file that builds fine from the CLI).
- App is **sandboxed** (`ENABLE_APP_SANDBOX = YES`, `ENABLE_USER_SELECTED_FILES =
  readonly`). Drag-drop grants read access; persisting a library needs
  security-scoped bookmarks (see Plan 5).
- Deployment target **macOS 15.6**, Swift language mode **5.0**.
- A `Stop` hook (`.claude/hooks/check-claude-md.sh`) blocks turns that change Swift
  without a *relevant* `CLAUDE.md` update — keep docs in sync per change.
