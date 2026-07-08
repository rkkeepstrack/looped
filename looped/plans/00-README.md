# `looped` — Improvement Plans

Five tracked problems, one plan file each. Each plan is self-contained: problem →
root cause (with `file:line` refs) → goal → step-by-step → files touched → risks →
acceptance criteria → open questions. **Each plan's top has a Status line — read it first.**

## Current status (2026-07-08) — START HERE

| # | Plan | Status |
|---|------|--------|
| 1 | [Waveform rendering](01-waveform-rendering.md) | ✅ **Done** (committed) |
| 2 | [Loop points](02-loop-points.md) | ✅ **Done** (committed) |
| 4 | [Architecture](04-architecture.md) | ✅ **Done** (committed `c725ddf`) |
| 3 | [UI redesign](03-ui-redesign.md) | ✅ **Done** (committed `a3ac513`) |
| 6 | [Bug fixes](06-bug-fixes.md) | 🟡 Partial — #1/#3/#6 done; #5 resolved by redesign; **#2/#4 folded into Plan 7** |
| 7 | [Waveform windowed rendering](07-waveform-windowed-rendering.md) | ⬜ Planned — **suggested next** (awaiting go); absorbs bug #2 (scrub highlight) & #4 (scroll-out-of-loop) |
| 5 | [Player features](05-player-features.md) | ⬜ Not started (library, drag-drop, loop nudge, pitch/rate) |

**Immediate pending action:** Plan 7 (windowed/"live" waveform rendering) is written
and awaiting the user's go. It replaces the full-width-layer render (which hits the
GPU texture limit and can't do long songs at zoom) with viewport-sized
`WaveformLiveCanvas` slices, adds a 20-min length limit, and folds in the
display-synced smooth pan. Nothing for it is coded yet.

Commit conventions: user commits directly to `main`; **only commit when asked**; never
commit `xcuserdata`. (`06-bug-fixes.md` is the user's bug list — now tracked/committed.)

## Recommended sequencing

1. ✅ Plan 4 — full service-oriented split (see plan 04's status for decisions).
2. ✅ Plan 2 — seamless `.loops` looping, crossfade, pitch/format fix.
3. ✅ Plan 1 — SoundCloud striped rendering, peak emphasis.
4. ✅ Plan 3 — mock layout: sidebar, header, bottom bar, theme; audio-derived width.
5. ⬜ **Plan 7 (next)** — windowed waveform rendering + 20-min limit + smooth pan.
6. ⬜ Plan 5 — library, click-to-play, drag & drop, loop nudge, pitch/rate + sync.

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
