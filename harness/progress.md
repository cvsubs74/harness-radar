# Progress log

Append-only. Each session adds an entry. Never rewrite history.

Format:

```
## YYYY-MM-DD HH:MM — <event>
- <bullet 1>
- <bullet 2>
```

Events include: `kickoff`, `F<NNN> <title>`, `retro F<NNN>`, `shipped F<NNN>`, `note`.

---

<!-- Future entries appended below. The first will be the /kickoff entry. -->

## 2026-05-26 19:02 — note
- Discussion-only session: assessed whether the engineering-workflow harness scales to complex server+client products.
- No code, features, or harness files changed. No /kickoff run yet — features.json still empty.
- Conclusion: harness discipline (acceptance criteria, ADRs, agent pipeline, append-only log) ports to any scale; specific tooling (features.json as SoT, one-feature-per-session, worktree parallelism) is sized for solo/small-team work.

## 2026-05-26 21:30 — note
- Harness rewrite: GitHub Issues are now the source of truth (features.json removed).
- Plan executed in 8 commits (c7b707b → 5c09f91): foundation scripts, GH issue forms/PR template/CODEOWNERS, agent specs, worktree scripts, slash commands, hooks, top-level docs, and final deletion of features.json + schema.
- Plan file: /Users/csubramanian@onetrust.com/.claude/plans/toasty-cooking-treehouse.md
- Outstanding: .claude/settings.json needs 4 new Bash permits for scripts/gh-*.sh (auto-mode classifier blocked the edit). Surfaced for manual application.
- Not pushed — local commits awaiting user's call on push.

## 2026-05-27 18:05 — kickoff
- Mode: github (cvsubs74/harness-radar, public)
- Spec: docs/spec.md — local CLI that reads gh + harness/progress.md and emits a velocity + harness-discipline report (lead time, throughput, agent-pipeline stage timings, AC re-edit smell detector).
- Epics filed: 5 (#1-#5)
- Stories filed: 21 (P0: 8, P1: 10, P2: 3; #6-#26), all sub-issue-linked to their epic, all on project #2, all on milestone v0.1
- Architecture: Python 3.11+ CLI, pipx-installed, stdlib sqlite3 cache, subprocess(gh) + jinja2 templating, src-layout, pytest+ruff
- ADR 0001: stack pick (harness/decisions/0001-stack.md) — rejected Node (better-sqlite3 native build threatened 60s install budget) and Go (overkill for 21-story MVP)
- Bootstrap audit: 1 closed spike issue (#27)
- Verify: bash harness/init.sh + bash harness/verify.sh both exit 0 (ruff clean, 1 smoke test passing)

## 2026-05-27 18:25 — #6 Add CLI entrypoint and --help
- PM: added 5th AC bullet for the no-args→help case (Summary said it but no AC enforced it; argparse default would silently exit 0).
- Implementer: stdlib argparse, `_CapitalUsageFormatter` to satisfy AC1's `Usage:` casing, explicit `len(argv)==0` short-circuit for AC3. 1 commit (2bb544e), 6/6 pytest, ruff clean.
- Tester evidence: posted on #6 (comment 4560048826), all 5 AC ticked.
- Reviewer: approved as comment (self-review can't formally --approve on GitHub). No blocking issues.
- PR: #30 — CI `verify` green.
- Baseline fixes discovered en route (committed straight to main as infra patches):
  - 85ae1a5: gh-project.sh `items(first: 200)` → `100` (GraphQL caps connections at 100). Bug #28 filed for proper pagination.
  - In-place fix to project board: Status field options corrected from defaults (Todo/In Progress/Done) to the harness-canonical (Todo/In progress/In review/Done) via updateProjectV2Field mutation. Bug #29 filed for gh-bootstrap.sh to detect+fix auto-created system fields.

## 2026-05-27 18:31 — shipped #6
- PR #30 squash-merged as 81312f9, remote and local branches deleted.
- Tracking: issue #6 auto-closed by `Closes #6`; project board → Done.


