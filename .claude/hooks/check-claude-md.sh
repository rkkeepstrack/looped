#!/usr/bin/env bash
# Stop hook: keep CLAUDE.md in sync with Swift source changes.
#
# Two-stage check:
#   1. Swift sources changed but CLAUDE.md untouched -> block (cheap, no LLM).
#   2. Both changed -> ask a fast headless `claude -p` whether the CLAUDE.md
#      edit actually reflects the doc-relevant Swift changes. Blocks only if
#      there are doc-relevant Swift changes the edit fails to cover, so a token
#      edit made just to satisfy stage 1 no longer passes.
#
# Stays silent on doc-only or no-op turns. Loop-safe via stop_hook_active and,
# for the nested `claude -p` call, via the CLAUDE_MD_CHECK_ACTIVE sentinel.

# The nested `claude -p` below runs its own Stop hook; this sentinel makes that
# nested invocation a no-op so we don't recurse (and rack up cost) forever.
if [ -n "$CLAUDE_MD_CHECK_ACTIVE" ]; then
  exit 0
fi

input=$(cat)

# Don't block twice in a row (prevents an infinite Stop->block->Stop loop).
if printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$repo_root" || exit 0

status=$(git status --porcelain 2>/dev/null) || exit 0

# Any Swift file changed (modified, added, staged, untracked)?
swift_changed=$(printf '%s\n' "$status" | grep -E '\.swift$' || true)
claude_changed=$(printf '%s\n' "$status" | grep -E 'CLAUDE\.md$' || true)

# Stage 1: code changed, docs untouched.
if [ -n "$swift_changed" ] && [ -z "$claude_changed" ]; then
  echo "Swift sources changed but CLAUDE.md was not updated. Review CLAUDE.md and update any affected section (architecture, file map, build/run, dependencies, conventions) before finishing. If no doc-relevant change occurred, no update is needed." >&2
  exit 2
fi

# Nothing more to verify unless BOTH changed.
if [ -z "$swift_changed" ] || [ -z "$claude_changed" ]; then
  exit 0
fi

# Stage 2: both changed -> verify the CLAUDE.md edit is relevant to the Swift
# changes. If the `claude` CLI is unavailable, fall back to the old behavior
# (any edit passes) rather than blocking real work.
command -v claude >/dev/null 2>&1 || exit 0

# Collect diffs vs HEAD (staged + unstaged). Cap size to keep the prompt small.
swift_diff=$(git diff HEAD -- '*.swift' 2>/dev/null | head -c 40000)
# Include contents of any brand-new (untracked) Swift files, which git diff omits.
untracked_swift=$(printf '%s\n' "$status" | grep -E '^\?\? .*\.swift$' | sed 's/^?? //')
if [ -n "$untracked_swift" ]; then
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    swift_diff="$swift_diff

--- NEW FILE: $f ---
$(head -c 8000 "$f")"
  done <<< "$untracked_swift"
fi
claude_diff=$(git diff HEAD -- CLAUDE.md '*/CLAUDE.md' 2>/dev/null | head -c 20000)
# Include contents of an untracked (not-yet-committed) CLAUDE.md, which git diff omits.
untracked_claude=$(printf '%s\n' "$status" | grep -E '^\?\? .*CLAUDE\.md$' | sed 's/^?? //')
if [ -n "$untracked_claude" ]; then
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    claude_diff="$claude_diff

--- NEW/UNTRACKED FILE: $f ---
$(head -c 20000 "$f")"
  done <<< "$untracked_claude"
fi

# Nothing substantive to compare -> don't block.
[ -n "$swift_diff" ] || exit 0

prompt="You are a documentation-sync gate for a repo whose CLAUDE.md documents architecture, the file map, build/run commands, dependencies, and conventions.

Below are the current uncommitted Swift changes and the current CLAUDE.md changes. Decide whether the CLAUDE.md edit adequately reflects any DOC-RELEVANT Swift changes — meaning changes that affect: the set/roles of files, the architecture or data flow, public methods/types named in the docs, build/run commands, dependencies, or conventions. Pure internal implementation tweaks (bug fixes, refactors with no doc-visible effect, comment/whitespace changes) are NOT doc-relevant.

Reply with EXACTLY one line, either:
  VERDICT: PASS
or
  VERDICT: FAIL — <one concise sentence naming the doc-relevant Swift change that CLAUDE.md fails to cover>

Rules:
- PASS if there are no doc-relevant Swift changes (regardless of what CLAUDE.md says).
- PASS if the CLAUDE.md edit reasonably covers the doc-relevant Swift changes.
- FAIL only if there IS a doc-relevant Swift change not reflected in the CLAUDE.md edit.
- Do not use any tools. Judge only from the text below.

=== SWIFT CHANGES ===
$swift_diff

=== CLAUDE.md CHANGES ===
$claude_diff"

verdict=$(CLAUDE_MD_CHECK_ACTIVE=1 claude -p "$prompt" \
  --model claude-haiku-4-5-20251001 </dev/null 2>/dev/null)

# If the judge produced no usable output, don't block.
printf '%s' "$verdict" | grep -q 'VERDICT:' || exit 0

if printf '%s' "$verdict" | grep -q 'VERDICT:[[:space:]]*FAIL'; then
  reason=$(printf '%s' "$verdict" | grep 'VERDICT:[[:space:]]*FAIL' | head -n1)
  echo "CLAUDE.md was edited, but the change does not cover a doc-relevant Swift change. $reason" >&2
  echo "Update the affected CLAUDE.md section (architecture, file map, build/run, dependencies, conventions) before finishing." >&2
  exit 2
fi

exit 0
