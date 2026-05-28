#!/usr/bin/env bash
# Stop-gate: block session termination on inconsistent state.
#
# Hard blocks (exit 2):
#   - On an issue-<n>-* branch and harness/verify.sh exits non-zero.
#   - Uncommitted changes on an issue-<n>-* branch where no PR is open.
#
# Soft warnings (printed to stderr but exit 0):
#   - No progress.md entry for today.
#   - Branch is ahead of origin with unpushed commits on an open PR.

set -u

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

problems=()
warnings=()

BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

# Extract issue number from branch, if applicable
N=""
case "$BRANCH" in
  issue-*)
    N=$(printf '%s' "$BRANCH" | sed -E 's/^issue-([0-9]+).*/\1/')
    [ "$N" = "$BRANCH" ] && N=""
    ;;
esac

# Hard block: on an issue branch and verify.sh is red
if [ -n "$N" ] && [ -x harness/verify.sh ]; then
  if ! bash harness/verify.sh >/dev/null 2>&1; then
    problems+=("On branch $BRANCH (issue #$N) but harness/verify.sh is red. Fix the baseline before stopping.")
  fi
fi

# Hard block: uncommitted changes on an issue branch with no open PR
if [ -n "$N" ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    has_pr=$(gh pr list --head "$BRANCH" --state open --json number --jq 'length' 2>/dev/null || echo 0)
    if [ "$has_pr" = "0" ]; then
      problems+=("Uncommitted changes on $BRANCH but no PR is open. Commit and open a PR, or stash.")
    fi
  fi
fi

# Soft warning: progress.md missing today's entry
today=$(date +%Y-%m-%d)
if [ -f harness/progress.md ]; then
  if ! grep -q "$today" harness/progress.md 2>/dev/null; then
    warnings+=("harness/progress.md has no entry for today ($today). Consider /retro or appending a note.")
  fi
fi

# Soft warning: unpushed commits on an open-PR branch
if [ -n "$N" ] && git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
  ahead=$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)
  if [ "$ahead" -gt 0 ]; then
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      has_pr=$(gh pr list --head "$BRANCH" --state open --json number --jq 'length' 2>/dev/null || echo 0)
      if [ "$has_pr" -gt 0 ]; then
        warnings+=("Branch is $ahead commit(s) ahead of origin/$BRANCH while a PR is open. Push before stopping.")
      fi
    fi
  fi
fi

# Print warnings (informational; doesn't block)
if [ ${#warnings[@]} -gt 0 ]; then
  echo "stop.sh: warnings:" >&2
  for w in "${warnings[@]}"; do echo "  - $w" >&2; done
fi

if [ ${#problems[@]} -eq 0 ]; then
  exit 0
fi

echo "stop.sh: blocking termination — fix these before ending the session:" >&2
for p in "${problems[@]}"; do echo "  - $p" >&2; done
exit 2
