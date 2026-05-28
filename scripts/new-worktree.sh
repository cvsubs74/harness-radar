#!/usr/bin/env bash
# new-worktree.sh — create a worktree for parallel work on a work item.
#
# Usage:
#   new-worktree.sh <issue-number>         # github mode (default)
#   new-worktree.sh task <T-NNN>           # local mode
#
# GitHub mode: creates ../<repo>-wt-issue-<n> on branch issue-<n>-<slug>
#   off main, fetches issue title via gh, and posts a comment on the issue
#   announcing the worktree.
#
# Local mode: reads the task block from harness/backlog.md, creates
#   ../<repo>-wt-task-<T-NNN> on branch task-<T-NNN>-<slug>, and updates
#   the task's `- Worktree: -` line in backlog.md to the new path.
#
# All state lives on GitHub (github mode) or harness/backlog.md (local mode).

set -euo pipefail

# ---------- arg parsing ----------

if [ $# -lt 1 ]; then
  echo "usage:" >&2
  echo "  $0 <issue-number>      # github mode" >&2
  echo "  $0 task <T-NNN>        # local mode" >&2
  exit 2
fi

MODE_FLAG="github"
if [ "$1" = "task" ]; then
  MODE_FLAG="task"
  shift
  if [ $# -ne 1 ]; then
    echo "usage: $0 task <T-NNN>" >&2
    exit 2
  fi
  TID="$1"
  case "$TID" in
    T-[0-9]*) ;;
    *) echo "error: task id must look like T-NNN (got: $TID)" >&2; exit 2 ;;
  esac
else
  N="${1#\#}"
  case "$N" in
    [0-9]*) ;;
    *) echo "error: issue number must be numeric (got: $1)" >&2; exit 2 ;;
  esac
fi

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# ============================================================
# GITHUB MODE
# ============================================================
if [ "$MODE_FLAG" = "github" ]; then
  command -v gh >/dev/null || { echo "error: gh CLI required" >&2; exit 1; }

  ISSUE_JSON=$(gh issue view "$N" --json title,state,number 2>/dev/null || true)
  if [ -z "$ISSUE_JSON" ]; then
    echo "error: issue #$N not found in this repo" >&2
    exit 1
  fi
  STATE=$(echo "$ISSUE_JSON" | jq -r .state)
  if [ "$STATE" != "OPEN" ]; then
    echo "error: issue #$N is $STATE; refusing to start a worktree on a closed issue" >&2
    exit 1
  fi

  TITLE=$(echo "$ISSUE_JSON" | jq -r .title)
  SLUG=$(printf '%s' "$TITLE" \
    | sed -E 's/^\[[^]]+\] *//' \
    | tr 'A-Z' 'a-z' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-40 \
    | sed -E 's/-+$//')
  [ -n "$SLUG" ] || SLUG="work"

  BRANCH="issue-${N}-${SLUG}"
  REPO_NAME="$(basename "$ROOT")"
  WT_PATH="$(cd .. && pwd)/${REPO_NAME}-wt-issue-${N}"

  [ ! -e "$WT_PATH" ] || { echo "error: $WT_PATH already exists" >&2; exit 1; }
  ! git show-ref --verify --quiet "refs/heads/$BRANCH" \
    || { echo "error: branch $BRANCH already exists" >&2; exit 1; }

  BASE_BRANCH="$(git symbolic-ref --short HEAD)"
  git worktree add -b "$BRANCH" "$WT_PATH" "$BASE_BRANCH"

  gh issue comment "$N" --body "Worktree opened: \`$WT_PATH\` on branch \`$BRANCH\`."

  echo
  echo "Worktree ready: $WT_PATH"
  echo "Branch:         $BRANCH"
  echo "Issue:          #$N — $TITLE"
  echo
  echo "Open a new terminal:"
  echo "  cd \"$WT_PATH\""
  echo "  claude"
  echo "  > /next"
  exit 0
fi

# ============================================================
# LOCAL (TASK) MODE
# ============================================================
[ -f harness/backlog.md ] || {
  echo "error: harness/backlog.md not found — local-mode worktrees require it" >&2
  exit 1
}

# Validate the task: must exist, Status: open, Type != epic. Capture title.
# Note: awk's `exit` inside a function still triggers END, so we use a `done`
# flag to prevent the second emit() call from double-printing.
VALIDATION=$(awk -v t="$TID" '
  function emit() {
    if (done) return
    if (id == t) {
      done = 1
      if (type == "epic") print "error:epic:" title
      else if (status != "open") print "error:not-open:" title " (status=" status ")"
      else print "ok:" title
      exit
    }
  }
  /^## T-/ { emit(); id=$2; title=$0; sub(/^## [^ ]+ . /, "", title); status=""; type=""; next }
  /^- Status: / { status=$3 }
  /^- Type: / { type=$3 }
  END { emit(); if (!done) print "error:not-found" }
' harness/backlog.md)

STATUS_PART="${VALIDATION%%:*}"
case "$STATUS_PART" in
  ok)
    TITLE="${VALIDATION#ok:}"
    ;;
  error)
    REST="${VALIDATION#error:}"
    KIND="${REST%%:*}"
    DETAIL="${REST#*:}"
    case "$KIND" in
      not-found) echo "error: task $TID not found in harness/backlog.md" >&2 ;;
      epic)      echo "error: task $TID is an epic ($DETAIL); refusing to start a worktree on an epic" >&2 ;;
      not-open)  echo "error: task $TID is not open: $DETAIL" >&2 ;;
      *)         echo "error: unexpected validation result: $VALIDATION" >&2 ;;
    esac
    exit 1
    ;;
  *)
    echo "error: unexpected validation result: $VALIDATION" >&2
    exit 1
    ;;
esac

SLUG=$(printf '%s' "$TITLE" \
  | sed -E 's/^\[[^]]+\] *//' \
  | tr 'A-Z' 'a-z' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
  | cut -c1-40 \
  | sed -E 's/-+$//')
[ -n "$SLUG" ] || SLUG="work"

BRANCH="task-${TID}-${SLUG}"
REPO_NAME="$(basename "$ROOT")"
WT_PATH="$(cd .. && pwd)/${REPO_NAME}-wt-task-${TID}"

[ ! -e "$WT_PATH" ] || { echo "error: $WT_PATH already exists" >&2; exit 1; }
! git show-ref --verify --quiet "refs/heads/$BRANCH" \
  || { echo "error: branch $BRANCH already exists" >&2; exit 1; }

BASE_BRANCH="$(git symbolic-ref --short HEAD)"
git worktree add -b "$BRANCH" "$WT_PATH" "$BASE_BRANCH"

# Update the task's `- Worktree: -` line in backlog.md (in the primary repo path,
# which IS this repo since worktree was just created — but the new branch is
# checked out in WT_PATH; backlog.md edits happen on the current branch).
TMP_BACKLOG=$(mktemp)
awk -v t="$TID" -v new_path="$WT_PATH" '
  /^## T-/ { id=$2 }
  id == t && /^- Worktree: / { print "- Worktree: " new_path; next }
  { print }
' harness/backlog.md > "$TMP_BACKLOG"
mv "$TMP_BACKLOG" harness/backlog.md

echo
echo "Worktree ready: $WT_PATH"
echo "Branch:         $BRANCH"
echo "Task:           $TID — $TITLE"
echo "Backlog:        harness/backlog.md updated (uncommitted)"
echo
echo "Commit the backlog update on the primary repo's branch:"
echo "  git -C \"$ROOT\" add harness/backlog.md"
echo "  git -C \"$ROOT\" commit -m \"log($TID): worktree opened at $(basename "$WT_PATH")\""
echo
echo "Open a new terminal:"
echo "  cd \"$WT_PATH\""
echo "  claude"
echo "  > /next"
