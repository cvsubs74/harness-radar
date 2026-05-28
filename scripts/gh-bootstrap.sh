#!/usr/bin/env bash
# gh-bootstrap.sh — Provision GitHub state for the engineering-workflow harness.
#
# Idempotent. Called from /start after `gh repo create`, and safe to re-run.
#
# Steps:
#   1. Preflight: gh >= 2.49, jq, auth scopes include `project`.
#   2. Sync labels from .github/labels.json (creates or updates).
#   3. Ensure milestone v0.1 exists.
#   4. Ensure a Projects v2 board (titled after the repo) exists with custom
#      fields Status / Estimate / Iteration / Worktree. Link it to the repo.
#   5. Write .github/project-config.json — owner, repo, project_number.
#
# NOT done here: branch protection. That's deferred to /kickoff's final step
# so the first CI run can establish the required-check name first.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# ---------- preflight ----------
command -v gh >/dev/null || { echo "error: gh CLI not installed (need >= 2.49)" >&2; exit 1; }
command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 1; }

GH_VERSION="$(gh --version | awk 'NR==1 {print $3}')"
NEED_VER="2.49.0"
if [ "$(printf '%s\n%s' "$NEED_VER" "$GH_VERSION" | sort -V | head -n1)" != "$NEED_VER" ]; then
  echo "error: gh $GH_VERSION found; need >= $NEED_VER (sub-issues REST API)" >&2
  echo "  Update with: brew upgrade gh   (or your package manager)" >&2
  exit 1
fi

AUTH_OUT="$(gh auth status 2>&1 || true)"
if ! echo "$AUTH_OUT" | grep -qE "(Token scopes|scopes):.*project"; then
  echo "error: gh CLI is missing the 'project' scope." >&2
  echo "  Run: gh auth refresh -s project,read:org" >&2
  exit 1
fi

REPO_NWO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
OWNER="${REPO_NWO%%/*}"
REPO="${REPO_NWO##*/}"
echo "Bootstrap target: $REPO_NWO"

LABELS_FILE=".github/labels.json"
if [ ! -f "$LABELS_FILE" ]; then
  echo "error: $LABELS_FILE not found" >&2
  exit 1
fi

# ---------- labels ----------
echo "Syncing labels from $LABELS_FILE..."
EXISTING_LABELS="$(gh label list --limit 200 --json name --jq '.[].name')"
jq -c '.labels[]' "$LABELS_FILE" | while read -r row; do
  name=$(echo "$row" | jq -r .name)
  color=$(echo "$row" | jq -r .color)
  desc=$(echo "$row" | jq -r .description)
  if echo "$EXISTING_LABELS" | grep -qxF "$name"; then
    gh label edit "$name" --color "$color" --description "$desc" >/dev/null
  else
    gh label create "$name" --color "$color" --description "$desc" >/dev/null
  fi
done

# ---------- milestone ----------
echo "Ensuring milestone v0.1..."
MS_NUM=$(gh api "repos/$REPO_NWO/milestones?state=open" --jq '.[] | select(.title == "v0.1") | .number' 2>/dev/null || true)
if [ -z "$MS_NUM" ]; then
  gh api --method POST "repos/$REPO_NWO/milestones" \
    -f title="v0.1" \
    -f description="Initial MVP release" >/dev/null
fi

# ---------- project board ----------
echo "Ensuring Projects v2 board titled '$REPO'..."
PROJECT_NUMBER=$(gh project list --owner "$OWNER" --format json \
  --jq ".projects[] | select(.title == \"$REPO\") | .number" 2>/dev/null | head -n1 || true)

if [ -z "$PROJECT_NUMBER" ]; then
  CREATE_OUT="$(gh project create --owner "$OWNER" --title "$REPO" --format json)"
  PROJECT_NUMBER=$(echo "$CREATE_OUT" | jq -r .number)
fi

if [ -z "$PROJECT_NUMBER" ] || [ "$PROJECT_NUMBER" = "null" ]; then
  echo "error: could not create or locate project for owner $OWNER" >&2
  exit 1
fi

gh project link "$PROJECT_NUMBER" --owner "$OWNER" --repo "$REPO_NWO" >/dev/null 2>&1 || true

# Ensure custom fields exist
FIELD_NAMES="$(gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json --jq '.fields[].name' 2>/dev/null || true)"

ensure_single_select() {
  local field="$1" options="$2"
  if ! echo "$FIELD_NAMES" | grep -qxF "$field"; then
    gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" \
      --name "$field" --data-type SINGLE_SELECT \
      --single-select-options "$options" >/dev/null
  fi
}

ensure_simple_field() {
  local field="$1" type="$2"
  if ! echo "$FIELD_NAMES" | grep -qxF "$field"; then
    gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" \
      --name "$field" --data-type "$type" >/dev/null
  fi
}

ensure_single_select "Status" "Todo,In progress,In review,Done"
ensure_simple_field "Estimate" "NUMBER"
# Iteration: gh project field-create does not accept --data-type ITERATION
# (Projects v2 Iteration fields need GraphQL with an iterations[] config).
# Skip with a warning; users can add manually in the project UI if desired.
if ! echo "$FIELD_NAMES" | grep -qxF "Iteration"; then
  echo "  (skip) Iteration field — create manually in the Projects v2 UI; gh CLI does not expose ITERATION data-type." >&2
fi
ensure_simple_field "Worktree" "TEXT"

# ---------- write project config ----------
mkdir -p .github
cat > .github/project-config.json <<EOF
{
  "owner": "$OWNER",
  "repo": "$REPO",
  "project_number": $PROJECT_NUMBER
}
EOF

echo
echo "Bootstrap complete."
echo "  Repo:      https://github.com/$REPO_NWO"
echo "  Project:   #$PROJECT_NUMBER (owner: $OWNER)"
echo "  Milestone: v0.1"
echo "  Labels:    $(jq '.labels | length' "$LABELS_FILE") synced"
echo
echo "Branch protection on main is deferred — /kickoff will enable it after the first CI run."
