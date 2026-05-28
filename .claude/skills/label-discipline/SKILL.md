---
name: label-discipline
description: Canonical label table for the engineering-workflow harness in github mode. Single source of truth for who owns which label and when each transition fires. GITHUB MODE ONLY — irrelevant in local tracking mode.
---

# Label discipline (github mode)

This skill applies only when `.claude/harness-mode.json` is `{"mode": "github"}`. In local mode, work-item state lives in `harness/backlog.md` as plain text; there are no labels.

## The canonical set

Synced from `.github/labels.json` by `scripts/gh-bootstrap.sh`. If a label is missing on the repo, re-run that script — it's idempotent.

### Type — what kind of work

| Label | Owner | Meaning |
|---|---|---|
| `type:epic` | product-manager | Cross-cutting capability spanning multiple stories. |
| `type:story` | anyone | A buildable, testable feature. The default. |
| `type:bug` | anyone | A defect to fix. Fast-path: skips backlog. |
| `type:spike` | architect | Time-boxed investigation or research. Often filed closed with an ADR link. |

### Priority — when to build

| Label | Owner | Meaning |
|---|---|---|
| `priority:P0` | **product-manager only** | Must build now. MVP-blocking. |
| `priority:P1` | **product-manager only** | Should build soon. Important but not blocking. |
| `priority:P2` | **product-manager only** | Nice to have. May be deferred. |

**Hard rule:** No agent other than product-manager applies or removes a `priority:*` label. If you think a priority is wrong, comment on the issue with rationale and ping product-manager. Don't self-promote.

### Area — where in the system

| Label | Owner | Meaning |
|---|---|---|
| `area:server` | anyone | Backend / API. |
| `area:client` | anyone | Frontend / UI. |
| `area:db` | anyone | Database / migrations. |
| `area:infra` | anyone | Build / deploy / CI / harness. |

Add more `area:*` entries by editing `.github/labels.json` and re-running `scripts/gh-bootstrap.sh`. Devops owns area changes during `/kickoff`.

### Meta — harness-internal

| Label | Owner | Meaning |
|---|---|---|
| `meta:blocked` | implementer / product-manager | Blocked on something external (vendor, decision, dependency). |
| `meta:needs-discussion` | anyone | Acceptance criteria need clarification. Tester emits this on ambiguous bullets. |
| `meta:bootstrap` | **harness only** | Created during `/kickoff` for audit trail. Don't apply by hand. |

## State transitions (the loop)

A story lifecycle, with the labels that gate each step:

```
[ filed ]
   │ product-manager triages → adds priority:P0|P1|P2
   ▼
[ priority:Px, type:story, area:X ]
   │ /next picks it, assigns @me, creates branch
   ▼
[ assignee = @me ]
   │ implementer builds, opens PR with Closes #N
   ▼
[ PR open ]
   │ tester ticks acceptance boxes with evidence
   ▼
[ all - [x] in body ]
   │ reviewer approves
   ▼
[ PR approved + CI green ]
   │ /ship squash-merges → Closes #N auto-closes the issue
   ▼
[ closed ]
```

Bug lifecycle is the same minus the "triage to priority" step — bugs are filed with `type:bug` and skip directly to `/next` pickup.

## Hook enforcement (if hooks are wired)

If the harness has `restricted-label-ownership.sh` as a `PreToolUse` hook, the following `gh` calls are blocked unless executed by the right role:

- `gh issue edit <n> --add-label "priority:*"` — product-manager only
- `gh issue edit <n> --remove-label "priority:*"` — product-manager only
- `gh issue edit <n> --add-label "meta:bootstrap"` — harness scripts only

The lean engineering-workflow setup does NOT ship this hook by default. Ownership is enforced by convention + this skill. If discipline starts slipping, port the hook from `cvsubs74/claude-workflow/.claude/hooks/restricted-label-ownership.sh`.

## Common mistakes

- **Adding `priority:P0` to your own newly-filed bug to "expedite" it.** It still has to flow through PM triage — they may agree or disagree on the priority. File it as `type:bug` (which already skips backlog) and let PM decide on `priority:*` separately.
- **Removing the `area:*` label because "it's obvious from the title".** The label is what powers `gh issue list --label area:server` for cross-cutting status views. Keep it.
- **Inventing a new `priority:P3` or `area:experimental` on the fly.** Add it to `.github/labels.json` and re-run `gh-bootstrap.sh` so it persists. Otherwise it's orphaned in the repo.

## Recovery

If labels drift (someone manually deleted one, or `gh-bootstrap.sh` failed mid-run):

```bash
bash scripts/gh-bootstrap.sh
```

Idempotent — only creates what's missing, edits color/description on what exists. Safe to re-run any time.
