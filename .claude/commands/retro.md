---
description: Write a retrospective for a shipped work item. Mode-aware — appends to progress.md in both modes; also posts to the closed GitHub issue in github mode.
allowed-tools: Bash, Read, Edit, Write
argument-hint: <issue-number|T-NNN>
---

# /retro $ARGUMENTS

Write a retrospective for the given shipped work item (or the most recently shipped if no argument). Append it to `harness/progress.md` AND (github mode only) post it as a final comment on the closed issue, so the audit trail lives on GitHub.

## Mode detection

```bash
MODE=$(jq -r '.mode // "github"' .claude/harness-mode.json 2>/dev/null || echo "github")
```

## Steps

### 1. Identify the work item

If `$ARGUMENTS` is provided:

- Looks like `T-NNN` → local task. Require `MODE=local`.
- Numeric → GitHub issue. Require `MODE=github`.

If `$ARGUMENTS` is empty, find the most recent shipped item from commit history:

**(github mode)**

```bash
N=$(git log --oneline -20 main | grep -oE '\(#[0-9]+\)' | head -1 | tr -d '()#')
```

**(local mode)**

```bash
TID=$(git log --oneline -20 main | grep -oE '\(T-[0-9]+\)' | head -1 | tr -d '()')
```

If empty, stop and ask the user to pass an explicit id.

### 2. Verify the item is closed

**(github mode)**

```bash
STATE=$(gh issue view "$N" --json state --jq .state)
[ "$STATE" = "CLOSED" ] || { echo "error: issue #$N is $STATE; only retro closed issues" >&2; exit 1; }
```

**(local mode)**

```bash
STATUS=$(awk -v t="^## $TID " '
  $0 ~ t { found=1; next }
  found && /^- Status: / { print $3; exit }
' harness/backlog.md)
[ "$STATUS" = "done" ] || { echo "error: task $TID is $STATUS; only retro done tasks" >&2; exit 1; }
```

### 3. Gather context

**(github mode)**

```bash
gh issue view "$N" --json title,body,labels
gh pr list --search "#$N" --state closed --json number,title,mergedAt --jq '.[0]'
git log --oneline --grep "#$N" -20
```

**(local mode)**

```bash
# Extract the task block from the backlog
awk -v t="^## $TID " '
  $0 ~ t { found=1; print; next }
  found && /^## T-/ { exit }
  found { print }
' harness/backlog.md
git log --oneline --grep "$TID" -20
```

### 4. Append to progress.md

```
## <YYYY-MM-DD HH:MM> — retro <#N or T-NNN>
- **What worked**: <1-3 bullets>
- **What didn't**: <1-3 bullets, or "nothing notable">
- **Surprises**: <anything learned mid-build>
- **Follow-ups**: <new issue numbers / task ids filed, or "none">
- **Memory candidates**: <facts worth saving to user/project memory, or "none">
```

### 5. Post the same retro **(github mode only)**

```bash
gh issue comment "$N" --body-file - <<'EOF'
### Retro

- **What worked**: ...
- **What didn't**: ...
- **Surprises**: ...
- **Follow-ups**: ...
EOF
```

In local mode, the progress.md entry IS the retro record. No GitHub comment surface.

### 6. File follow-up work items (if any)

**(github mode)** For each follow-up:

```bash
gh issue create \
  --title "<title>" \
  --label "type:story,priority:P2,area:<name>" \
  --body "Follow-up from retro of #$N: <one-line context>"
```

**(local mode)** For each follow-up, append a new task to `harness/backlog.md` (use the next free `T-NNN`).

Update the progress.md "Follow-ups" line with the new ids.

### 7. Commit

```bash
git add harness/progress.md
[ "$MODE" = "local" ] && git add harness/backlog.md
git commit -m "log(retro): <#N|T-NNN>"
git push
```

## Notes

- Retros are short. Three bullets per section is the cap.
- If the retro surfaces blocking work, file it as `priority:P1`, not `P2`.
- Memory candidates: facts that are non-obvious and useful for *future* sessions. Skip if nothing genuinely surprising came up — saving routine entries dilutes memory.
