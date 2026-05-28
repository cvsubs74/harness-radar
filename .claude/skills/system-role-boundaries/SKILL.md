---
name: system-role-boundaries
description: Single source of truth for which agent owns which artifact, state transition, and label in the engineering-workflow harness. Read at cold-start, consulted before any agent picks up a task.
---

# System role boundaries

Six specialist agents. One pipeline per task. No agent does another agent's job.

## The pipeline (per task, end-to-end)

```
product-manager → [architect, if cross-cutting] → implementer → tester → reviewer → /ship
```

- **product-manager** picks up first, canonicalizes the task body, hands to next.
- **architect** is invoked **only** when the task crosses module boundaries or adds a dependency. Skipped for in-module changes.
- **implementer** writes code.
- **tester** ticks acceptance boxes with evidence.
- **reviewer** approves the PR or blocks on real issues.
- **devops** is **not** in the per-task pipeline. It's invoked at `/kickoff` (fills `init.sh` / `verify.sh` / `ci.yml`) and during `/next` only if a task adds infrastructure.

The user runs `/ship` to merge.

## Ownership matrix

| Artifact / state | Owned by | Notes |
|---|---|---|
| Task body (canonical schema) | product-manager | Re-canonicalizes on every touch. |
| `### Acceptance criteria` checkboxes | **tester only** | With evidence posted as a comment (GitHub mode) or as a checked-box line below the bullet (local mode). |
| Closing a task | merge (via `Closes #N`) in GitHub mode; `/ship` (which flips `Status: done` in `harness/backlog.md`) in local mode | Implementer/tester/reviewer NEVER manually close. |
| `priority:P0` / `P1` / `P2` label | **product-manager only** | No self-promotion by other roles. |
| `area:*` / `type:*` labels | anyone | Anyone can apply; PM normalizes. |
| `meta:*` labels | harness only | Set by `/kickoff` and `/init-mode`; never by hand. |
| `docs/architecture.md` | **architect only** | Implementer reads but doesn't extend. |
| `harness/decisions/NNNN-*.md` (ADRs) | **architect only** | Each significant ADR also files a closed `type:spike` issue (GitHub mode) or a `### ADR-NNNN` row in `harness/backlog.md` (local mode). |
| `harness/init.sh` / `harness/verify.sh` | **devops only** | Implementer doesn't edit verify.sh to make the test pass. |
| `.github/workflows/ci.yml` | **devops only** | Job name stays `verify` — branch protection depends on it. |
| `docs/runbook.md` | **devops** primary; implementer adds ops notes for new deps | |
| `docs/spec.md` | user + product-manager | Source of truth for what the product is. |
| `harness/backlog.md` (local mode) | tester appends acceptance ticks; product-manager seeds + canonicalizes; implementer flips `Status:`; reviewer doesn't edit | Same evidence discipline as GitHub mode. |
| PR body (`Closes #N` or `Refs #N`) | implementer | Reviewer can request changes but doesn't rewrite. |
| `.claude/agents/*.md` | the named agent only | Edits go through a separate PR — see `skill-maintenance`. |
| `.claude/skills/*/SKILL.md` | anyone with the rationale | Edits go through a separate PR — see `skill-maintenance`. |

## Hard rules (boundary violations to refuse)

- **Implementer must not tick acceptance boxes.** Tester's job, with evidence.
- **Implementer must not edit acceptance criteria.** Product-manager owns the task body.
- **Tester must not modify code to make the test pass.** If the test is wrong, return to implementer.
- **Reviewer must not approve a PR whose acceptance boxes aren't all ticked.** Tester gates that.
- **Architect must not write production code.** ADRs and `docs/architecture.md` only.
- **Product-manager must not close issues.** Merge closes them via `Closes #N` (GitHub) or `/ship` flips status (local).
- **Anyone-but-PM applying `priority:*` is a hook violation in GitHub mode.** See `label-discipline`.

## Cold-start checklist (every session)

Before picking up any task:

1. Read `CLAUDE.md` — the harness contract.
2. Read this file (`system-role-boundaries`) — who does what.
3. Read `docs/spec.md` — what the product is.
4. Read `docs/architecture.md` — how the system fits together.
5. If GitHub mode: `gh issue list --assignee @me`. If local mode: top open in `harness/backlog.md`.
6. Run `harness/init.sh` and `harness/verify.sh` — confirm baseline.
7. Then, and only then, pick a task.

Steps 1–4 are once-per-session. Steps 5–6 are every session.

## When in doubt

If you can't tell whose job something is, it's the **user's**. Ask. The harness exists to coordinate work; if the role table doesn't cover the case, surface it rather than guessing.
