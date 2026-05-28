---
name: file-bug
description: Canonical protocol for filing a bug report. Mode-aware — files a GitHub Issue in github mode, appends to harness/backlog.md in local mode. Same repro / hypothesis / severity discipline either way.
---

# Filing a bug

Bugs are filed when an actual regression or defect is found. Not when something is hard to use, slow, or undesigned — those are stories / enhancements.

The protocol below produces a high-signal report: a repro, a hypothesis, and a severity, in five minutes or less. Whoever picks up the bug (the implementer, typically) starts from a real trail instead of a complaint.

## When to file vs when to fix in-line

Inline fix (no bug filing):

- You broke it in your own branch and you're about to fix it. Fix it.
- A trivial typo or dead-link in docs you're already editing.

File a bug:

- A live production behavior is wrong.
- A test that used to pass is now failing without your changes.
- Someone else's code path produces incorrect output.
- A user-reported issue you can't immediately fix in your current PR.

## The body (both modes)

```
### Repro
1. <step>
2. <step>
3. <step>

### Expected
<one sentence>

### Actual
<one sentence>

### Evidence
<command output, stack trace, screenshot link, etc.>

### Hypothesis
<your best guess at root cause, in one or two sentences. "Unknown" is fine if you really don't know.>

### Severity
P0 — production is broken / data loss / auth bypass
P1 — major feature broken or major user impact, workaround exists
P2 — cosmetic, minor impact, edge case

### Area
<server | client | db | infra>
```

All seven sections required. If a section would be empty, write "n/a" — don't drop it. The schema is positional; downstream consumers (the implementer, tester) parse it.

## Filing — github mode

```bash
gh issue create \
  --title "[Bug] <one-line description>" \
  --label "type:bug,priority:P<n>,area:<x>" \
  --body "$(cat <<'EOF'
### Repro
1. ...

### Expected
...

### Actual
...

### Evidence
...

### Hypothesis
...

### Severity
P<n> — <one-line rationale>

### Area
<area>
EOF
)"
```

Notes:

- Bugs **skip the backlog** — they go straight into PM's queue and Dev can pick them up immediately. No `meta:backlog` label.
- `priority:*` on a bug is the **filer's** initial assessment. PM may adjust on triage. (This is the one case where a non-PM applies `priority:*` initially — PM owns final calibration. See `label-discipline`.)
- After filing, post the issue number in chat / PR description so the user knows where to follow.

## Filing — local mode

Append to `harness/backlog.md`. The next available ID is one above the max `T-NNN` already present.

```markdown
## T-042 — [Bug] <one-line description>
- Type: bug
- Priority: P1
- Area: server
- Status: open
- Worktree: -
- Filed: 2026-05-27 by cvsubs74

### Repro
1. ...

### Expected
...

### Actual
...

### Evidence
...

### Hypothesis
...

### Severity
P1 — major feature broken; workaround exists

### Acceptance
- [ ] Bug is reproducible against current main
- [ ] Fix lands with regression test that fails before fix and passes after
- [ ] Behavior in `Actual` no longer occurs
```

Notes:

- Append-only — never edit older entries except to flip the `Status:` line and tick `- [ ]` boxes.
- The `Acceptance` section is what the tester verifies before flipping `Status: done`. Each bug gets a minimum 3-bullet acceptance unless you have a strong reason to deviate.

## Triage / pickup

GitHub mode: PM (or operator) reviews the new bug, may adjust `priority:*`, then `/next` (or the implementer directly) picks it up.

Local mode: Same flow but on `harness/backlog.md`. PM is generally less necessary in local mode because the operator IS the PM.

## Duplicates

Before filing:

- GitHub mode: `gh issue list --label type:bug --state open` and grep for similar.
- Local mode: search `harness/backlog.md` for the keyword.

If a duplicate exists, comment / append a note to the existing entry rather than filing a new one. Use the new evidence to strengthen the existing report.

## Hard rules

- **Don't file a bug for missing-feature work.** That's a story (or enhancement). Bug = regression.
- **Don't file a bug without a repro.** "It's slow" without numbers / steps is not a bug. Get numbers, file the bug.
- **Don't escalate severity to get attention.** P0 means production is broken. Cosmetic bugs are P2 even if they annoy you. PM gets the final calibration.
- **Don't fix a bug you just filed without leaving a paper trail.** File first, fix second. The trail matters for retros and regression analysis.
