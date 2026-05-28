#!/usr/bin/env bash
# gh-sub-issue.sh <parent-issue> <child-issue>
#
# Links <child> as a sub-issue of <parent> via the GitHub REST sub-issues API.
# Requires gh >= 2.49. Accepts numbers with or without leading '#'.
#
# Sharp edge: the REST endpoint
#   POST /repos/{owner}/{repo}/issues/{parent}/sub_issues
# takes the CHILD'S NUMERIC REST ID (the large `id` field returned by the
# /issues/{n} endpoint), not the user-facing #number. We resolve it here.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <parent-issue> <child-issue>" >&2
  exit 2
fi

parent="${1#\#}"
child="${2#\#}"

REPO_NWO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

child_rest_id=$(gh api "repos/$REPO_NWO/issues/$child" --jq .id 2>/dev/null || true)
if [ -z "$child_rest_id" ] || [ "$child_rest_id" = "null" ]; then
  echo "error: could not resolve issue #$child to a REST id (does it exist?)" >&2
  exit 1
fi

gh api --method POST "repos/$REPO_NWO/issues/$parent/sub_issues" \
  -F sub_issue_id="$child_rest_id" >/dev/null

echo "Linked #$child as sub-issue of #$parent"
