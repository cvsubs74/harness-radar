#!/usr/bin/env bash
# merge-worktree.sh
#
# Run from inside a worktree. Verifies locally, pushes the branch, opens a PR
# via gh if one isn't already open. Does NOT merge locally — branch protection
# on main and `/ship` finish the job.
#
# Branch naming:
#   - issue-<n>-<slug>     — github mode; PR body uses "Closes #<n>".
#   - task-T-NNN-<slug>    — local mode;  PR body uses "Refs T-NNN".

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

command -v gh >/dev/null || { echo "error: gh CLI required" >&2; exit 1; }

BRANCH="$(git symbolic-ref --short HEAD)"

MODE_FLAG=""
N=""
TID=""
case "$BRANCH" in
  issue-*)
    MODE_FLAG="github"
    N=$(printf '%s' "$BRANCH" | sed -E 's/^issue-([0-9]+).*/\1/')
    if [ -z "$N" ] || [ "$N" = "$BRANCH" ]; then
      echo "error: could not extract issue number from branch '$BRANCH'" >&2
      exit 1
    fi
    ;;
  task-T-*)
    MODE_FLAG="task"
    TID=$(printf '%s' "$BRANCH" | sed -E 's/^task-(T-[0-9]+).*/\1/')
    if [ -z "$TID" ] || [ "$TID" = "$BRANCH" ]; then
      echo "error: could not extract task id from branch '$BRANCH'" >&2
      exit 1
    fi
    ;;
  *)
    echo "error: not on a recognized worktree branch (currently on $BRANCH)" >&2
    echo "       expected issue-<n>-* or task-T-NNN-*" >&2
    exit 1
    ;;
esac

if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree not clean — commit or stash before /ship" >&2
  exit 1
fi

echo "Running verify.sh in worktree..."
bash harness/verify.sh

echo "Pushing $BRANCH to origin..."
git push -u origin "$BRANCH"

EXISTING_PR=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null || true)
if [ -z "$EXISTING_PR" ] || [ "$EXISTING_PR" = "null" ]; then
  if [ "$MODE_FLAG" = "github" ]; then
    TITLE=$(gh issue view "$N" --json title --jq .title 2>/dev/null || echo "$BRANCH")
    gh pr create --base main --head "$BRANCH" \
      --title "$TITLE (#$N)" \
      --body "Closes #${N}"
  else
    # local-mode: pull title from backlog.md
    TITLE=$(awk -v t="$TID" '
      $0 ~ "^## " t " " { title=$0; sub(/.* - /, "", title); print title; exit }
    ' harness/backlog.md)
    [ -n "$TITLE" ] || TITLE="$BRANCH"
    gh pr create --base main --head "$BRANCH" \
      --title "$TITLE ($TID)" \
      --body "Refs ${TID}

Closes the task in \`harness/backlog.md\`. \`/ship\` will flip its Status to done after merge."
  fi
  EXISTING_PR=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number')
fi

echo
echo "PR #$EXISTING_PR open against main. Awaiting CI + review."
echo "Run /ship to merge once CI is green and the reviewer has approved."
