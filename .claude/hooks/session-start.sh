#!/usr/bin/env bash
# Session-start banner: orient any new Claude session against the project's
# tracking mode (github | local). Output goes to additionalContext for the model.

set -u

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

echo "=== engineering-workflow harness ==="
echo "cwd: $(pwd)"

# --- mode detection ---
MODE_FILE=".claude/harness-mode.json"
if [ -f "$MODE_FILE" ]; then
  MODE=$(jq -r '.mode // "github"' "$MODE_FILE" 2>/dev/null || echo "github")
else
  MODE="unset"
fi
echo "mode: $MODE"
echo

if [ "$MODE" = "unset" ]; then
  echo "--- tracking mode not configured ---"
  echo "  This project has no .claude/harness-mode.json."
  echo "  Run /init-mode github   — to use GitHub Issues + Projects v2 as the source of truth"
  echo "  Run /init-mode local    — to use harness/backlog.md as the source of truth"
  echo "  Assuming 'github' until set."
  echo
  MODE="github"
fi

# --- git context (both modes) ---
if [ -d .git ]; then
  echo "--- last 5 commits ---"
  git log --oneline -5 2>/dev/null || echo "(no commits yet)"
  echo
  BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "(detached)")
  echo "--- branch ---"
  echo "$BRANCH"
  echo
fi

# ============================================================
# GITHUB MODE
# ============================================================
if [ "$MODE" = "github" ]; then
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && git remote get-url origin >/dev/null 2>&1; then
    # If on an issue-<n>-* branch, surface the linked issue.
    case "${BRANCH:-}" in
      issue-*)
        N=$(printf '%s' "$BRANCH" | sed -E 's/^issue-([0-9]+).*/\1/')
        if [ -n "$N" ] && [ "$N" != "$BRANCH" ]; then
          echo "--- linked issue ---"
          gh issue view "$N" --json number,title,state,labels,assignees \
            --jq '"#\(.number) [\(.state)] \(.title)\n  labels: \(.labels | map(.name) | join(", "))\n  assignees: \(.assignees | map(.login) | join(", "))"' 2>/dev/null \
            || echo "(could not fetch issue #$N)"
          echo
        fi
        ;;
    esac

    echo "--- open issues assigned to you ---"
    gh issue list --assignee @me --state open --limit 10 \
      --json number,title,labels \
      --jq '.[] | "  #\(.number) \(.title)  [\(.labels | map(.name) | join(","))]"' 2>/dev/null \
      || echo "  (gh issue list failed)"
    echo

    echo "--- open PRs ---"
    gh pr list --state open --limit 10 \
      --json number,title,headRefName,isDraft,statusCheckRollup,reviewDecision \
      --jq '.[] | "  #\(.number) \(.title)  (\(.headRefName)) \(.reviewDecision // "no-review") \(.isDraft|if . then "DRAFT" else "" end)"' 2>/dev/null \
      || echo "  (gh pr list failed)"
    echo

    # Next pick — what /next would choose
    echo "--- next pick (/next) ---"
    if NEXT_N=$(bash scripts/gh-next-issue.sh 2>/dev/null); then
      gh issue view "$NEXT_N" --json number,title,labels \
        --jq '"  #\(.number) \(.title)  [\(.labels | map(.name) | join(","))]"' 2>/dev/null \
        || echo "  #$NEXT_N"
    else
      echo "  (no open unassigned stories)"
    fi
    echo
  else
    echo "--- GitHub state ---"
    echo "  (gh not installed, not authenticated, or no remote — run /start to set up,"
    echo "   or /init-mode local if this project doesn't use GitHub Issues)"
    echo
  fi
fi

# ============================================================
# LOCAL MODE
# ============================================================
if [ "$MODE" = "local" ]; then
  BACKLOG="harness/backlog.md"
  if [ -f "$BACKLOG" ]; then
    # If on a task-T-NNN-* branch, surface the linked task header.
    case "${BRANCH:-}" in
      task-T-*)
        TID=$(printf '%s' "$BRANCH" | sed -E 's/^task-(T-[0-9]+).*/\1/')
        if [ -n "$TID" ] && [ "$TID" != "$BRANCH" ]; then
          echo "--- linked task ---"
          awk -v t="^## $TID " '
            $0 ~ t { found=1; print; next }
            found && /^## T-/ { exit }
            found { print }
          ' "$BACKLOG" | head -15
          echo
        fi
        ;;
    esac

    echo "--- top open tasks (P0 first, then P1, P2) ---"
    for PRIO in P0 P1 P2; do
      awk -v want_prio="$PRIO" '
        function emit() {
          if (id != "" && open && prio == want_prio) print "  " title
        }
        /^## T-/ { emit(); id=$2; title=$0; open=0; prio=""; next }
        /^- Status: open$/ { open=1 }
        /^- Priority: / { prio=$3 }
        END { emit() }
      ' "$BACKLOG" | head -5
    done
    echo

    # Open PRs still come from gh (PRs work in both modes)
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && git remote get-url origin >/dev/null 2>&1; then
      echo "--- open PRs ---"
      gh pr list --state open --limit 10 \
        --json number,title,headRefName \
        --jq '.[] | "  #\(.number) \(.title)  (\(.headRefName))"' 2>/dev/null \
        || echo "  (gh pr list failed)"
      echo
    fi

    # Counts by status
    echo "--- task counts ---"
    for STAT in open in-progress in-review done; do
      COUNT=$(grep -c "^- Status: $STAT$" "$BACKLOG" 2>/dev/null) || COUNT=0
      echo "  $STAT: $COUNT"
    done
    echo
  else
    echo "--- local backlog ---"
    echo "  $BACKLOG not found. Run /kickoff to seed it, or /init-mode github to switch."
    echo
  fi
fi

# --- progress log (both modes) ---
if [ -f harness/progress.md ]; then
  echo "--- last progress entry ---"
  tail -n 20 harness/progress.md
  echo
fi

# --- next-action hint ---
if [ "$MODE" = "github" ]; then
  echo "Next: read CLAUDE.md and run /next (or /start if this is a fresh boilerplate, or /kickoff after /start)."
elif [ "$MODE" = "local" ]; then
  echo "Next: read CLAUDE.md and run /next (picks top P0 task from harness/backlog.md). /init-mode github to switch."
fi
