---
description: Set or change this project's tracking mode (github | local). Writes .claude/harness-mode.json. Optionally migrates between modes.
allowed-tools: Bash, Read, Write, Edit
---

# /init-mode `<github|local>`

The engineering-workflow harness supports two backlog tracking modes per project:

- **`github`** — GitHub Issues + sub-issues + Projects v2 are the source of truth. Every story / bug / epic is a `gh` issue; `/next` picks via `scripts/gh-next-issue.sh`.
- **`local`** — `harness/backlog.md` is the source of truth. Tasks are appended as `## T-NNN — <title>` blocks; `/next` picks the highest-priority open task. PRs to GitHub still work (PR mechanics aren't mode-specific).

This command sets the mode for the current project and (optionally) migrates between them.

## Preconditions

1. `pwd` is the project root (`.claude/` is present).
2. Git remote `origin` is configured (`git remote get-url origin`). PRs still go to GitHub in both modes, so an origin is expected. If absent, the command still writes the config but warns that `/ship` will only commit locally.

## Steps

### 1. Parse argument

Argument is `github` or `local`. If anything else (or no argument), print the help block and stop:

```
Usage: /init-mode github|local

  github  GitHub Issues + Projects v2 are the source of truth.
  local   harness/backlog.md is the source of truth.

Current mode (if any):
  $(cat .claude/harness-mode.json 2>/dev/null | jq -r .mode 2>/dev/null || echo "not set")
```

### 2. Detect current mode

```bash
CURRENT=$(jq -r .mode .claude/harness-mode.json 2>/dev/null || echo "unset")
```

### 3. If same mode, no-op

```bash
if [ "$CURRENT" = "$NEW_MODE" ]; then
  echo "Already in $NEW_MODE mode. No change."
  exit 0
fi
```

### 4. If switching, offer migration

Ask the user (via plain stdout — `/init-mode` is interactive in plan flow):

- **github → local:** "Dump open issues into `harness/backlog.md`? (y/n)"
  - If yes: run `gh issue list --state open --json number,title,body,labels` and append each as a `T-NNN` entry with priority/area parsed from labels. Issues stay open on GitHub; this is a read-only export.
  - If no: skip. Future `/next` will use `harness/backlog.md` (which may be empty); existing GitHub issues stay in place but `/next` won't see them.

- **local → github:** "File each open `harness/backlog.md` task as a GitHub Issue? (y/n)"
  - If yes: for each open task, `gh issue create` with the canonical schema, append the GitHub issue number to the task entry (`- GitHub: #<n>`), and flip the task's `Status: open` → `Status: migrated`.
  - If no: skip. Future `/next` will use GitHub; the local backlog entries remain but are no longer picked up.

In either direction, the migration is a one-shot dump. After it, the new mode is authoritative.

### 5. Write the config

```bash
mkdir -p .claude
cat > .claude/harness-mode.json <<EOF
{
  "mode": "$NEW_MODE",
  "set_at": "$(date -u +%Y-%m-%d)",
  "set_by": "$(git config user.name 2>/dev/null || whoami)",
  "previous_mode": "$([ "$CURRENT" = "unset" ] && echo null || echo "\"$CURRENT\"")"
}
EOF
```

### 6. Local-mode bootstrap (only when switching to local)

If `NEW_MODE == local` and `harness/backlog.md` doesn't exist:

```bash
cat > harness/backlog.md <<'EOF'
# Backlog (local mode)

Append-only task list. The harness reads this in local mode the same way it reads GitHub Issues in github mode.

Format per entry:

```
## T-NNN — <Title>
- Type: story | bug | spike | epic
- Priority: P0 | P1 | P2
- Area: <one-word>
- Status: open | in-progress | in-review | done
- Worktree: <path or "->
- Filed: YYYY-MM-DD by <git user>

### Summary
<1-3 sentences>

### Acceptance criteria
- [ ] <testable bullet 1>
- [ ] <testable bullet 2>

### Notes
<optional>
```

T-NNN IDs are zero-padded sequential. Append at the bottom; never reorder.

---

<!-- entries appended below -->
EOF
```

### 7. Report

Print:

```
Mode: <new mode> set.
Config: .claude/harness-mode.json
Previous: <previous mode>
Backlog: <github | harness/backlog.md>

Next:
  /status     see current state in the new mode
  /next       pick the next task in the new mode
  /kickoff    re-seed forward work if the new mode's backlog is empty
```

## Hard rules

- **Never delete the previous mode's tracking data without asking.** When migrating, the prior surface (GitHub issues or `harness/backlog.md`) is preserved — the operator can clean up later.
- **The migration step is one-shot.** Re-running `/init-mode` on the same mode is a no-op; switching modes after migration won't re-migrate. Manual sync afterward.
- **`Closes #N` still applies in local mode IF an issue number was recorded** (via local→github migration). Don't break the PR ↔ task link.
