#!/usr/bin/env bash
# gh-next-issue.sh — print the next issue number to work on, or exit non-zero.
#
# Strategy: open, no assignee, not an epic, ordered priority:P0 → P1 → P2,
# then by creation date ascending. Prints only the issue number; nothing else
# on stdout. Replaces the jq-on-features.json query used by /next pre-rewrite.

set -euo pipefail

for prio in P0 P1 P2; do
  num=$(gh issue list \
    --search "is:issue is:open no:assignee -label:type:epic label:priority:$prio sort:created-asc" \
    --json number \
    --jq '.[0].number' 2>/dev/null || true)
  if [ -n "$num" ] && [ "$num" != "null" ]; then
    echo "$num"
    exit 0
  fi
done

echo "error: no open unassigned non-epic issues found" >&2
exit 1
