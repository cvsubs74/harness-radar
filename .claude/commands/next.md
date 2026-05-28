---
description: Build the next highest-priority open work item, end to end. Mode-aware — picks a GitHub Issue in github mode or a T-NNN task from harness/backlog.md in local mode.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# /next

Build **one** work item, sequentially, on a new branch off `main`. Use `/parallel <id>` instead if you want to work in a worktree.

## Mode detection

```bash
MODE=$(jq -r '.mode // "github"' .claude/harness-mode.json 2>/dev/null || echo "github")
```

## Steps

### 1. Verify baseline

```bash
pwd
git status                  # working tree must be clean
git log --oneline -5
bash harness/init.sh
bash harness/verify.sh      # must exit 0
```

If `verify.sh` fails, **stop**. Fix the baseline as its own commit on `main` before picking work.

### 2. Pick the work item

**(github mode)**

```bash
N=$(bash scripts/gh-next-issue.sh)
TITLE=$(gh issue view "$N" --json title --jq .title)
echo "Building issue #$N — $TITLE"
```

`N` is the issue number. If the script exits non-zero, the backlog is empty or every story/bug is assigned — tell the user, stop.

**(local mode)**

```bash
# Pick highest-priority (P0 > P1 > P2), lowest-numbered, open task.
T=$(awk '
  function emit() {
    if (id != "" && open && prio != "") print prio, id, title
  }
  /^## T-/ { emit(); id=$2; title=$0; sub(/.* - /, "", title); open=0; prio=""; next }
  /^- Status: open$/ { open=1 }
  /^- Priority: / { prio=$3 }
  END { emit() }
' harness/backlog.md | sort -k1,1 -k2,2 | head -1)

[ -n "$T" ] || { echo "no open tasks in harness/backlog.md"; exit 1; }
TID=$(echo "$T" | awk '{print $2}')
TITLE=$(echo "$T" | sed 's/^[^ ]* [^ ]* //')
echo "Building task $TID — $TITLE"
```

If no open task exists, tell the user; stop.

### 3. Claim the work item

**(github mode)**

```bash
gh issue edit "$N" --add-assignee @me
bash scripts/gh-project.sh set-status "$N" "In progress"
```

**(local mode)**

Edit `harness/backlog.md`: under the task block for `$TID`, change the `- Status: open` line to `- Status: in-progress`. Preserve everything else.

### 4. Create the branch

Derive a slug from the title (lowercase, alnum + hyphens, max 40 chars).

**(github mode)** — branch name: `issue-<n>-<slug>`.

```bash
git checkout main
git pull --ff-only
git checkout -b "issue-${N}-<slug>"
```

**(local mode)** — branch name: `task-<TID>-<slug>` (e.g. `task-T-007-add-password-reset`).

```bash
git checkout main
git pull --ff-only
git checkout -b "task-${TID}-<slug>"
```

### 5. Run the agent pipeline

Dispatch in order (mode-agnostic):

1. **product-manager** — re-read the work item body. Canonicalize the schema if needed. Flag ambiguous acceptance.
2. **architect** — only if the work item is `type:epic`-spanning or labeled `area:*` for a new domain.
3. **implementer** — write code. Commit messages format: `<type>(<area>): <subject> (#<N>)` in github mode, `<type>(<area>): <subject> (<TID>)` in local mode.
4. **tester** — runs `verify.sh`, posts evidence, ticks `### Acceptance criteria` checkboxes (only the tester touches those).
5. **reviewer** — runs after the PR is open (step 7); blocks via `gh pr review --request-changes`.

### 6. Push the branch

```bash
git push -u origin "$(git symbolic-ref --short HEAD)"
```

### 7. Open the PR

**(github mode)**

```bash
gh pr create --base main --head "issue-${N}-<slug>" \
  --title "$TITLE (#$N)" \
  --body "Closes #$N"
bash scripts/gh-project.sh set-status "$N" "In review"
```

**(local mode)**

```bash
gh pr create --base main --head "task-${TID}-<slug>" \
  --title "$TITLE ($TID)" \
  --body "Refs $TID

Closes the task in \`harness/backlog.md\`. \`/ship\` will flip its Status to done after merge."
```

Also edit the task block in `harness/backlog.md`: `- Status: in-progress` → `- Status: in-review`.

Now invoke the **reviewer** agent on the open PR.

### 8. Append progress.md entry

```
## <YYYY-MM-DD HH:MM> — <#N or T-NNN> <title>
- Implementer: <one-line approach>
- Tester evidence: posted (issue comment | inline in backlog.md)
- PR: #<pr-number>
- Reviewer: approved | changes requested
```

Commit and push:

```bash
git add harness/progress.md harness/backlog.md   # backlog.md only in local mode
git commit -m "log(<#N|T-NNN>): session note"
git push
```

### 9. Hand off

Tell the user: PR URL, current state ("In review" until reviewer approves and CI is green), next command (`/ship`).

## Hard rules

- **Do not edit `### Acceptance criteria`** to make a check pass. Push back to product-manager if it's wrong.
- **Do not touch other work items** in the same session. If you find a blocker, file a new one (`gh issue create` in github mode, append to `harness/backlog.md` in local mode) and stop.
- **Do not skip `verify.sh`.** It must be green before *and* after.
- **Do not merge the PR yourself.** `/ship` does that, after reviewer approves and CI is green.
- **One work item per session.** When the PR is open and reviewer-approved, stop. `/ship` is a separate step.
