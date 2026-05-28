---
description: Merge a PR back into main and clean up. Mode-aware — auto-closes the GitHub issue (github mode) or flips the task to Status: done (local mode).
allowed-tools: Bash, Read, Edit
---

# /ship

Squash-merge the PR for the current branch into `main`, confirm the work item is closed, move the project card to Done (github mode), and remove the worktree if applicable.

## Mode detection

```bash
MODE=$(jq -r '.mode // "github"' .claude/harness-mode.json 2>/dev/null || echo "github")
```

## Preconditions

You are on a branch named `issue-<n>-*` (github mode) or `task-T-NNN-*` (local mode), either in the main repo path or in its worktree.

The PR for this branch is OPEN, CI is GREEN, and the reviewer has APPROVED (or the harness is solo and you're self-approving — branch protection still requires CI).

## Steps

### 1. Extract id from branch

```bash
BRANCH=$(git symbolic-ref --short HEAD)
case "$BRANCH" in
  issue-*)
    [ "$MODE" = "github" ] || { echo "error: on issue-* branch but mode is $MODE" >&2; exit 1; }
    N=$(echo "$BRANCH" | sed -E 's/^issue-([0-9]+).*/\1/')
    ;;
  task-T-*)
    [ "$MODE" = "local" ] || { echo "error: on task-* branch but mode is $MODE" >&2; exit 1; }
    TID=$(echo "$BRANCH" | sed -E 's/^task-(T-[0-9]+).*/\1/')
    ;;
  *)
    echo "error: not on an issue-* or task-* branch ($BRANCH)" >&2
    exit 1
    ;;
esac
```

### 2. Verify locally

```bash
git status                  # clean
bash harness/verify.sh      # exit 0
```

### 3. Push any final commits and confirm PR state (both modes)

```bash
git push
PR=$(gh pr list --head "$BRANCH" --json number,state,mergeable --jq '.[0]')
[ -n "$PR" ] || { echo "error: no PR for $BRANCH — open one manually or via scripts/merge-worktree.sh" >&2; exit 1; }
echo "$PR" | jq -e '.state == "OPEN" and .mergeable == "MERGEABLE"' >/dev/null \
  || { echo "error: PR not mergeable. State: $PR"; exit 1; }
```

### 4. Confirm CI is green and review is approved

```bash
PR_NUM=$(echo "$PR" | jq -r .number)
gh pr checks "$PR_NUM" --required   # exits non-zero if any required check is failing/pending
gh pr view "$PR_NUM" --json reviewDecision --jq '.reviewDecision' \
  | grep -qE '^(APPROVED|null)$'    # APPROVED, or null if no protection enforced reviews
```

If checks aren't green, stop. Branch protection will block the merge anyway — surface the failing check to the user.

### 5. Merge

```bash
gh pr merge "$PR_NUM" --squash --delete-branch
```

This squash-merges into `main` and deletes the remote branch.

**(github mode)** The PR body's `Closes #$N` auto-closes the issue.

**(local mode)** The PR body's `Refs $TID` does NOT auto-close anything on GitHub — step 6 flips the task block in `harness/backlog.md`.

### 6. Update the tracking surface

**(github mode)**

```bash
bash scripts/gh-project.sh set-status "$N" "Done"
```

**(local mode)**

Edit `harness/backlog.md`: in the task block for `$TID`, change `- Status: in-review` (or whatever status) to `- Status: done`. Optionally append a `- Shipped: <YYYY-MM-DD>` line just below `- Status:`.

### 7. Clean up the local branch and worktree (both modes)

If we're in a worktree:

```bash
WT_ROOT=$(git rev-parse --show-toplevel)
MAIN_ROOT=$(git worktree list --porcelain | awk '$1=="worktree"{p=$2} $1=="branch" && $2 ~ /^refs\/heads\/main$/ {print p; exit}')
cd "$MAIN_ROOT"
git fetch --prune
git worktree remove "$WT_ROOT"
git branch -D "$BRANCH" 2>/dev/null || true
```

If we're in the main repo:

```bash
git checkout main
git pull --ff-only
git branch -D "$BRANCH" 2>/dev/null || true
```

### 8. Append progress.md entry

On `main`:

```
## <YYYY-MM-DD HH:MM> — shipped <#N or T-NNN>
- PR #<pr-num>, squash-merged, branch deleted
- Tracking: <issue closed | task → Status: done>
```

Commit + push:

```bash
git add harness/progress.md
[ "$MODE" = "local" ] && git add harness/backlog.md
git commit -m "log(ship): <#N|T-NNN> shipped"
git push
```

### 9. Report

Print:

```
✓ Shipped <#N or T-NNN>.
  PR:        <url>
  Tracking:  <issue closed | task → done>
  Board:     Done (github mode)
Recent log:
  <git log --oneline -5>
```

## Failure handling

- **Required check failing:** surface which check, link to its run, stop. Don't override.
- **Merge conflict:** `gh pr merge` will report it. Tell the user to rebase locally on `main`, push, and re-run `/ship`. Don't auto-resolve.
- **Worktree remove fails:** typically means uncommitted state. Surface, ask the user.
