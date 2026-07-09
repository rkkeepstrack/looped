# 04 — Loop-point nudge arrows

**Depends on:** nothing (independent of the library work).
**Scope:** wire the disabled `«`/`»` buttons in the Loop panel to fine-adjust A/B.

## Current state (anchors)

- Buttons exist, disabled: `ControlsView.swift` → `LoopPanel.loopRow` (chevron
  buttons with `.disabled(true) // nudge → Plan 5`).
- Loop state: `PlayerViewModel.loopStart/loopEnd` (`(TimeInterval?, AVAudioFramePosition?)`
  tuples), `setLoopStart/End(time:)` → `refreshLoop()` re-slices + re-arms via
  `LoopingService.makeLoopBuffer` + `PlaybackService.scheduleLoop`.

## Design

- `PlayerViewModel.nudgeLoopStart(by: TimeInterval)` / `nudgeLoopEnd(by:)`:
  new time = old + delta, clamped to `[0, duration]` **and** so A < B stays true
  (min gap: one crossfade length — see note), then reuse `setLoopStart/End` (which
  re-arms via `refreshLoop()`).
- Step: **±0.05 s** per click; **⌥-click = ±0.01 s** (fine), **⇧-click = ±0.5 s**
  (coarse). Read modifiers via `NSEvent.modifierFlags` at action time (SwiftUI
  `Button` doesn't expose them).
- No-op when the point isn't set (buttons stay disabled until A/B set — keeps the
  current visual affordance meaningful).

## Technical notes (researched)

- Re-arming reschedules the loop buffer from scratch (`player.stop()` inside
  `scheduleLoop`) — playback position restarts at A on every nudge. That's the
  existing `setLoopStart/End` behavior, acceptable for v1; smooth "keep position"
  nudging would need `scheduleLoop` to accept a start offset (out of scope, note it).
- **Min A–B gap:** `DefaultLoopingService.crossfadeSeam` self-limits its fade to
  `min(12 ms, loopFrames/4, available)` (`LoopingService.swift:59`), so tiny loops
  don't crash — but a sub-perceptual loop is useless anyway. Clamp the nudge to a
  simple `B − A ≥ 0.05 s`.

## Steps

1. `nudgeLoopStart/End(by:)` + clamping tests (bounds, A<B, min gap, unset no-op).
2. Enable the chevron buttons; wire with modifier-aware step; tooltip shows the steps.
3. `CLAUDE.md` + `plans/README.md`.

## Acceptance

- [ ] `«`/`»` shift the set point by 0.05 s (⌥ 0.01 s, ⇧ 0.5 s) and re-arm the loop.
- [ ] Clamped: A ≥ 0, B ≤ duration, A < B with a safe minimum gap.
- [ ] Unset points: arrows disabled.
