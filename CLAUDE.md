# Harness contract for this project

You are working inside a repository that uses the **engineering-workflow** harness. The harness drives state via `gh` + local files.

This file is the contract every Claude session in this repo must follow.

## Tracking mode

This harness supports **two tracking modes** per project, picked at the first session via `/init-mode`:

- **`github`** — GitHub Issues + sub-issues + Projects v2 are the source of truth. `gh issue list`, `gh issue create`, `/next` via `scripts/gh-next-issue.sh`. Default for any project that has a GitHub remote and wants the visible project-board surface.
- **`local`** — `harness/backlog.md` is the source of truth. Tasks live as `## T-NNN — <title>` blocks; `/next` picks the highest-priority open task by parsing the file. PRs still go to GitHub if a remote exists.

Both modes share the same agent pipeline, branch naming, PR flow, and acceptance-criteria discipline. They differ only in **where work items live**. PR mechanics (open → review → squash-merge) work in both modes because PRs go to GitHub regardless of tracking surface.

If `.claude/harness-mode.json` is absent, the harness assumes `github` for backward compatibility and the session-start banner prints a reminder to run `/init-mode <github|local>`.

When this document says "issue" without a qualifier, it means whichever surface the active mode uses — a GitHub Issue in `github` mode, a `T-NNN` task block in `local` mode. Sections that are mode-specific are tagged **(github mode)** or **(local mode)**.

## The protocol (every session, every time)

1. Run `pwd` and confirm you are at the project root.
2. Read the last 5 commits: `git log --oneline -5`.
3. Run `harness/init.sh` to bring up the dev environment.
4. Run `harness/verify.sh` to confirm a green baseline. If it fails, **stop and fix the baseline before anything else.**
5. Check active state:
   - **(github mode)** `gh issue list --assignee @me --state open` + `gh pr list --state open`.
   - **(local mode)** Top open tasks from `harness/backlog.md` (the session-start banner surfaces these) + `gh pr list --state open` if a remote exists.
6. Read `harness/progress.md` (the personal session log — informational, not authoritative).
7. Pick **exactly one** open work item:
   - **(github mode)** an issue with `priority:P0`/`P1`/`P2` label, no assignee, no `type:epic` label.
   - **(local mode)** a task with `Priority: P0|P1|P2` and `Status: open` from `harness/backlog.md`.
8. Build it using the agent pipeline below.
9. Open a PR with `Closes #<n>` (github mode) or `Refs T-NNN` (local mode) in the body.
10. Append a dated entry to `harness/progress.md`. Push.

## Agent pipeline for one issue

For each issue, dispatch agents in this order. Each agent is under `.claude/agents/`.

1. **product-manager** — re-read the issue body. If acceptance criteria are ambiguous, refine them in the issue body *only after* the user confirms (or, in auto mode, choose the most reasonable interpretation and document it in `harness/decisions/`). Canonicalize body schema if a human re-edited the issue.
2. **architect** — invoked only if the issue crosses module boundaries or introduces new dependencies. Updates `docs/architecture.md` if needed, files a closed `type:spike` issue for the ADR (github mode) or a `Type: spike, Status: done` task block (local mode).
3. **implementer** — writes the code. Touches application code, not the harness. Commit messages use `<type>(<area>): <subject> (#<n>)` in github mode, `<type>(<area>): <subject> (T-NNN)` in local mode.
4. **tester** — runs `harness/verify.sh` plus an end-to-end check matching the acceptance criteria. Posts evidence as a comment on the issue (github mode) or as a checked-box line in `backlog.md` (local mode). Ticks `### Acceptance criteria` checkboxes only with evidence.
5. **reviewer** — reads the PR diff via `gh pr diff`. Approves via `gh pr review --approve` or blocks via `--request-changes`. Blocks only on real issues (correctness, security, obvious smell).

After PR is open, CI green, and reviewer approves: `/ship` merges. The PR's `Closes #<n>` auto-closes the issue (github mode); in local mode, `/ship` flips `Status: done` in `backlog.md`.

## Hard rules

- **Do not edit `### Acceptance criteria`** to make a check pass. The harness exists to prevent this. If acceptance is wrong, surface to user.
- **One issue per session.** Even if you have time. Long sessions on multiple issues lead to merge pain and bad handoffs.
- **Active surface is the source of truth** for what is and isn't done — GitHub Issues in github mode, `harness/backlog.md` in local mode. Chat memory and `progress.md` are not.
- **Append, never rewrite** `harness/progress.md`. It's a personal session log, not authoritative — but history is still load-bearing for retros.
- **Never `--no-verify` a commit.** If a hook fails, fix the cause.
- **Worktrees only via `/parallel <id>`.** Don't hand-roll `git worktree add` — the script ensures the branch name and the tracking-surface update stay consistent.
- **Commit messages reference the work-item id.**

## Picking the next issue

When `/next` is invoked:

**(github mode)**

1. `bash scripts/gh-next-issue.sh` prints the next issue number (open, no assignee, not an epic, ordered priority P0→P1→P2 then by issue number).
2. `gh issue edit <n> --add-assignee @me` to claim it.
3. `bash scripts/gh-project.sh set-status <n> "In progress"` to move the project card.
4. Create a branch off `main`: `issue-<n>-<slug>`. The slug derives from the issue title (see `scripts/new-worktree.sh` for the canonical recipe).

**(local mode)**

1. Parse `harness/backlog.md` for the highest-priority (P0 > P1 > P2), lowest-numbered task with `Status: open`.
2. Edit that task's `Status: open` → `Status: in-progress` in place.
3. Create a branch off `main`: `task-T-NNN-<slug>`. The slug derives from the task title.

## Parallel issue work

`/parallel <id>` runs `scripts/new-worktree.sh <id>`:

**(github mode)** — `<id>` is the issue number.

1. Validates the issue is OPEN, unassigned, and not an epic.
2. Creates `../<repo>-wt-issue-<n>` on branch `issue-<n>-<slug>`.
3. Posts a comment on the issue announcing the worktree path.

**(local mode)** — `<id>` is `task T-NNN`.

1. Validates the task exists, has `Status: open`, and is not `Type: epic`.
2. Creates `../<repo>-wt-task-T-NNN` on branch `task-T-NNN-<slug>`.
3. Updates the task's `- Worktree:` line in `backlog.md` to the new path.

Open a new `claude` session inside the worktree. *That* session executes the protocol above. When the PR is reviewed and CI is green, run `/ship` from the worktree — it merges via `gh pr merge --squash --delete-branch` and tears down the worktree.

## When you are blocked

- Missing acceptance detail → ask the user once; if no answer and auto mode, pick the simplest interpretation, edit the issue body to reflect it, and write an ADR under `harness/decisions/`.
- Verify failing for unrelated reasons → fix the baseline first, commit that as its own change on `main` (it's not branch-protection-bypassable for non-trivial changes; if branch protection blocks, surface to user).
- Stack not initialized (`init.sh` / `verify.sh` are still templates) → invoke the **devops** agent to fill them in.
- `gh auth` missing scopes (typically `project` for board mutations) → run `gh auth refresh -s project,read:org` and re-try.

## What lives where

| Concern | Where |
|---|---|
| Tracking mode | `.claude/harness-mode.json` |
| Product vision and requirements | `docs/spec.md` |
| Cross-cutting technical design | `docs/architecture.md` |
| Operational runbook | `docs/runbook.md` |
| **Backlog (source of truth) — github mode** | **GitHub Issues** (`gh issue list`) |
| **Backlog (source of truth) — local mode** | **`harness/backlog.md`** |
| **Epic → story hierarchy — github mode** | **GitHub sub-issues** (via REST `/sub_issues`) |
| **Epic → story hierarchy — local mode** | `Parent: T-NNN` field on the child task |
| **Status — github mode** | **Projects v2 custom field** (Todo / In progress / In review / Done) |
| **Status — local mode** | `Status:` line in the task block (`open` / `in-progress` / `in-review` / `done`) |
| **Priority, area, type — github mode** | **GitHub labels** (`priority:P0`, `area:auth`, `type:story`) |
| **Priority, area, type — local mode** | `Priority:` / `Area:` / `Type:` lines in the task block |
| **Releases — github mode** | **GitHub Milestones** (`v0.1`, `v0.2`, …) |
| **Releases — local mode** | `Milestone:` line in the task block (optional) |
| **Decisions and tradeoffs** | `harness/decisions/NNNN-<topic>.md` + closed `type:spike` issue (github) / spike task (local) |
| **Personal session log** | `harness/progress.md` (informational only; mode-agnostic) |
| Bring up dev environment | `harness/init.sh` (mode-agnostic) |
| End-to-end smoke test | `harness/verify.sh` (mode-agnostic) |
| Slash commands | `.claude/commands/` |
| Specialized agents | `.claude/agents/` |
| Shared skills (cross-agent rules) | `.claude/skills/` |
| Hooks | `.claude/hooks/` |
| GitHub provisioning (github mode only) | `scripts/gh-bootstrap.sh` + `.github/labels.json` |

## Canonical issue body schema **(github mode)**

Every story issue body MUST use this exact structure. The PM agent re-canonicalizes any human edits back to this form. Tester parses positionally.

```
### Parent epic
#<n>   (or "standalone")

### Priority
P0   (with rationale)

### Area
<one-word>

### Summary
<1-3 sentences>

### Acceptance criteria
- [ ] <testable bullet 1>
- [ ] <testable bullet 2>

### Non-goals
- <optional>

### Notes
<optional>
```

Headings are `### ` (h3) to match what GitHub issue forms render.

## Canonical task block schema **(local mode)**

In local mode, each task is a block in `harness/backlog.md`. Same evidence and acceptance discipline; different surface.

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

T-NNN IDs are zero-padded sequential. Append new tasks at the bottom; never reorder. Tester ticks `- [ ]` boxes only with evidence (a brief comment line below the bullet, since there's no GitHub comment surface in local mode). PM and tester own the same gates they do in github mode — see `.claude/skills/system-role-boundaries/SKILL.md`.

## Entry points

| Command | When to use |
|---|---|
| `/start` | First session after cloning. Wizard that drafts `docs/spec.md`, **(github mode)** creates a GitHub repo + bootstraps labels/milestone/project board, then runs `/kickoff`. **(local mode)** skips the GitHub repo step and just initialises the local backlog. |
| `/init-mode <github\|local>` | Set or change this project's tracking mode. Optionally migrates open work between surfaces. Run once at the start of a new project. |
| `/kickoff` | Power-user alternative to `/start`'s wizard: you already wrote `docs/spec.md` by hand. Seeds issues (github mode) or `backlog.md` tasks (local mode), drafts architecture, fills init/verify, enables branch protection if a remote exists. |
| `/next` | Every subsequent session. Builds the next top-priority work item. |
| `/parallel <id>` | Spin off concurrent work in a git worktree. `<id>` is an issue number in github mode or `T-NNN` in local mode. |
| `/status` | See backlog (issue counts / task counts) + open PRs + project board URL (github mode only). |
| `/verify` | Read-only sanity check of the dev environment. Mode-agnostic. |
| `/retro <id>` | Post-task reflection appended to `progress.md` AND **(github mode)** posted as a comment on the closed issue. |
| `/ship` | Squash-merge the PR for the current branch, close the work item (`Closes #N` auto-closes in github mode; `Status: done` flip in local mode), tear down the worktree. |

## Session-end checklist

Before stopping, confirm:

- [ ] `harness/verify.sh` exits 0.
- [ ] If a PR is open on this branch, it's pushed to `origin`.
- [ ] If you ticked acceptance boxes, the evidence is recorded (issue comment in github mode, checked-box in `backlog.md` in local mode).
- [ ] `harness/progress.md` has a new entry for this session (warning, not blocker).
- [ ] `git status` is clean.

The `stop.sh` hook blocks termination only on hard inconsistencies (issue branch with red verify, or uncommitted changes on an issue branch with no open PR). Soft warnings are printed but don't block.

## Shared skills

Cross-agent rules and procedures that all agents consult. Read at cold-start. Each skill is ≤ 200 lines.

- `system-role-boundaries` — who owns what label / artifact / state transition.
- `worktree-management` — git worktree protocol, cleanup discipline.
- `label-discipline` — canonical label table + ownership rules (github mode only).
- `file-bug` — bug-filing protocol, mode-aware.
- `skill-maintenance` — agent-doc-PR pattern, line-cap discipline.

Resist adding more without genuine cross-agent reuse — see `skill-maintenance` for the test.
