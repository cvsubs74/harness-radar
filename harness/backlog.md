# Backlog (local mode)

> This file is the **local-mode task backlog**. It only becomes the active source of truth when `.claude/harness-mode.json` is set to `{"mode": "local"}` (via `/init-mode local`).
>
> In `github` mode, this file is documentation only — the active backlog lives on GitHub Issues. The harness's slash commands read whichever surface the active mode says is authoritative.

---

Append-only task list. The harness reads this in local mode the same way it reads GitHub Issues in github mode.

Format per entry:

```
## T-NNN — <Title>
- Type: story | bug | spike | epic
- Priority: P0 | P1 | P2
- Area: <one-word>
- Status: open | in-progress | in-review | done
- Worktree: <path or "-">
- Filed: YYYY-MM-DD by <git user>

### Summary
<1-3 sentences>

### Acceptance criteria
- [ ] <testable bullet 1>
- [ ] <testable bullet 2>

### Notes
<optional>
```

T-NNN IDs are zero-padded sequential (T-001, T-002, ..., T-099, T-100, ...). Append at the bottom; never reorder. Closed tasks (`Status: done`) stay in place for audit trail.

The same evidence discipline as GitHub mode applies:

- Only the **tester** ticks acceptance boxes, after evidence.
- Only the **product-manager** assigns `Priority:`.
- The **implementer** flips `Status:` from `open` → `in-progress` on pickup; the tester flips it to `in-review` when the PR is open.
- `/ship` flips `Status: in-review` → `Status: done` after PR merge.

For bug filings, see `.claude/skills/file-bug/SKILL.md` (the local-mode block).

---

<!-- entries appended below -->
