---
description: Spawn a git worktree for parallel work on a work item. Mode-aware — accepts an issue number in github mode or T-NNN in local mode.
allowed-tools: Bash, Read, Edit
argument-hint: <issue-number|T-NNN>
---

# /parallel $ARGUMENTS

Create an isolated git worktree so another Claude session can build the given work item in parallel without conflicting with the current session.

## Mode detection

```bash
MODE=$(jq -r '.mode // "github"' .claude/harness-mode.json 2>/dev/null || echo "github")
```

## Steps

### 1. Identify the work item from $ARGUMENTS

- If `$ARGUMENTS` is a bare number (or `#NNN`) → treat as a GitHub issue number; require `MODE=github`.
- If `$ARGUMENTS` matches `T-[0-9]+` → treat as a local task ID; require `MODE=local`.
- Anything else → stop with usage hint.

```
Usage:
  /parallel 42       — GitHub mode, issue #42
  /parallel T-007    — local mode, task T-007
```

### 2. Validate the work item

**(github mode)**

```bash
N="${ARGUMENTS#\#}"
gh issue view "$N" --json state,assignees,labels --jq \
  'if .state != "OPEN" then "error:not-open"
   elif (.assignees | length) > 0 then "error:assigned"
   elif (.labels | map(.name) | index("type:epic")) then "error:epic"
   else "ok" end'
```

Stop with the matching error if not `ok`.

**(local mode)**

```bash
TID="$ARGUMENTS"
# The task must exist and be Status: open
awk -v t="^## $TID " '
  $0 ~ t { found=1; matched_status=0; matched_type=0; next }
  found && /^## T-/ { exit }
  found && /^- Status: open$/ { matched_status=1 }
  found && /^- Type: epic$/ { matched_type=1 }
  END { if (!found) print "error:not-found"
        else if (matched_type) print "error:epic"
        else if (!matched_status) print "error:not-open"
        else print "ok" }
' harness/backlog.md
```

Stop with the matching error if not `ok`.

### 3. Create the worktree

**(github mode)**

```bash
bash scripts/new-worktree.sh "$N"
```

Creates `../<repo>-wt-issue-$N` on branch `issue-$N-<slug>` and posts a comment on the issue announcing the worktree path.

**(local mode)**

```bash
bash scripts/new-worktree.sh task "$TID"
```

Creates `../<repo>-wt-task-$TID` on branch `task-$TID-<slug>` and updates the task block in `harness/backlog.md` — the `- Worktree: -` line becomes `- Worktree: ../<repo>-wt-task-$TID`. The script leaves the `backlog.md` edit uncommitted in the primary repo and prints the commit command for you to run.

### 4. Print instructions

```
Worktree ready at <path>. Open a new terminal:

  cd <path>
  claude
  > /next

That session will pick up the work item on this branch automatically.
When done, run /ship from inside the worktree to push, open a PR, and merge.
```

## Notes

- Don't enter the worktree from this session. The point is a fresh Claude session per worktree.
- If `scripts/new-worktree.sh` fails, surface the error verbatim — it already prints clear messages.
- **(github mode)** Worktree path is recorded only as a comment on the issue. No local state file.
- **(local mode)** Worktree path is recorded on the task's `- Worktree:` line in `harness/backlog.md`. That line is the audit trail.
