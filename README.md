# engineering-workflow

A boilerplate for building **any product** with a team of Claude Code agents. Pick **GitHub-tracked** or **local-only** state per project — same agent pipeline either way.

This repo ships a pre-wired **harness** — agent roles, slash commands, shared skills, hooks, scripts, and (optional) GitHub provisioning — so that long-running agent work survives context resets and many parallel sessions. The design follows the patterns in Anthropic's [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents).

## What you get

- **Dual tracking mode (per project)** picked at first session via `/init-mode`:
  - **`github`** — Backlog lives as GitHub Issues. Epics → stories link via the sub-issues API. Status / Estimate / Worktree fields live on a Projects v2 board. Priority / area / type are labels.
  - **`local`**  — Backlog lives in `harness/backlog.md` as `T-NNN` task blocks. Same evidence/acceptance discipline; no GitHub Issues required.
  - Both modes share the same agent pipeline, branch naming, PR flow.
- **Specialized agents** under `.claude/agents/` — product-manager, architect, implementer, tester, reviewer, devops.
- **Slash commands** under `.claude/commands/` — `/start`, `/init-mode`, `/kickoff`, `/next`, `/parallel`, `/verify`, `/status`, `/retro`, `/ship`. All mode-aware.
- **Shared skills** under `.claude/skills/` — `system-role-boundaries`, `worktree-management`, `label-discipline`, `file-bug`, `skill-maintenance`. Cross-agent rules, each ≤ 200 lines.
- **Hooks** under `.claude/hooks/` — mode-aware session-start banner; stop-gate that blocks termination on inconsistent state.
- **Provisioning scripts** under `scripts/` — `gh-bootstrap.sh`, `gh-sub-issue.sh`, `gh-project.sh`, `gh-next-issue.sh`, plus worktree helpers that handle both issue-`<n>` and task-`T-NNN` branches.
- **GitHub assets** under `.github/` (github mode) — issue forms (epic, story, bug, spike), PR template, CODEOWNERS, labels.json, CI workflow.
- **Worktree-based parallelism** so multiple Claude sessions can build independent issues / tasks concurrently.
- **Stack-agnostic.** `init.sh` and `verify.sh` are templates the devops agent fills in on first kickoff.

## Prerequisites

- **`gh` CLI ≥ 2.49** (github mode only) — sub-issues REST API is GA from January 2025. Install via `brew install gh` (macOS) or your platform equivalent. Not needed for local mode, except for PR operations.
- **`gh auth login` completed** (github mode only) with scopes including `repo`, `read:org`, and `project`. If you forgot `project`, run `gh auth refresh -s project,read:org`. (`gh auth refresh` is interactive — run it in a TTY, not via `!` in Claude Code.)
- **`jq`** — used by label sync, project lookups, and the mode-aware session-start banner.
- **`git`** (both modes) — worktrees + branch/PR mechanics.

## Quick start

```bash
git clone https://github.com/cvsubs74/engineering-workflow my-product
cd my-product
claude
> /init-mode github          # or local
> /start                     # or /kickoff if you already have docs/spec.md
```

### Mode choice

- **`github` mode** is the default. Pick it if you have or want a GitHub repo, want a Projects v2 board, and want issue/PR discipline visible on github.com.
- **`local` mode** keeps everything inside the repo. Pick it for personal projects, sensitive work, or anywhere you don't want a GitHub Issues surface. PRs still work if you push to a remote.

You can switch modes later with `/init-mode <github|local>` — the command offers a one-shot migration in either direction.

### `/start` (github mode, full wizard)

`/start` in github mode:

1. Preflights `gh` (version + auth scopes); errors out with install/refresh hints if missing.
2. Detaches your new directory from the boilerplate's git history (`rm -rf .git && git init -b main`).
3. Asks ~8 conversational questions about what you're building and drafts `docs/spec.md`.
4. Shows you the draft and lets you edit before saving.
5. **Creates a GitHub repo** (private by default; asks for account/visibility).
6. Personalizes `.github/CODEOWNERS` with your GitHub login.
7. Pushes the initial commit.
8. Runs `scripts/gh-bootstrap.sh` to sync labels, create the `v0.1` milestone, and provision a Projects v2 board with Status / Estimate / Worktree fields. *(Note: the Iteration field isn't auto-created — `gh project field-create` doesn't expose `ITERATION` as a data type; add via UI if you want iteration planning.)*
9. Hands off to `/kickoff` — dispatches product-manager (files issues + sub-issue links), architect (drafts architecture, files ADR-0001 as a closed spike issue), and devops (fills `init.sh`/`verify.sh`/CI). Watches the first CI run and enables branch protection on `main` requiring the `verify` check.
10. Prints a next-steps banner with the project board URL, issue counts, and `/status`, `/next`, `/parallel`.

### `/start` (local mode)

Skips the GitHub repo creation + provisioning steps. Drafts `docs/spec.md`, then `/kickoff` seeds `harness/backlog.md` with `T-NNN` task blocks, drafts architecture, fills init/verify. Branch protection still applies *if* you later add a GitHub remote.

After kickoff, every new session is just:

```
> /next                    # pick the top P0 work item, create branch, run pipeline, open PR
# or
> /parallel 42             # github mode — build issue #42 in an isolated worktree
> /parallel task T-007     # local mode  — build task T-007  in an isolated worktree
```

### What you'll see on GitHub after `/start` + `/kickoff`

- A new repo, private (or public if you chose).
- Labels synced from `.github/labels.json` — `type:*`, `priority:*`, `area:*`, `meta:*`.
- A `v0.1` milestone.
- A Projects v2 board (titled after your repo) with custom fields Status, Estimate, Iteration, Worktree.
- 3-6 epic issues + 15-30 story issues, organized as sub-issues under their parent epic, all on the project board with Status=Todo.
- 4 closed `meta:bootstrap` issues forming the audit trail for what kickoff did (init.sh, verify.sh, CI, ADR-0001).
- `main` is protected: the `verify` CI check must pass before any PR can merge. Squash-merge with auto-delete-branch is the default.

### Power-user path (skip the wizard)

If you'd rather edit `docs/spec.md` by hand and create the GitHub repo yourself:

```bash
git clone https://github.com/cvsubs74/engineering-workflow my-product
cd my-product
rm -rf .git && git init -b main
$EDITOR docs/spec.md
# create + push to GitHub manually, then:
sed -i.bak "s/PLACEHOLDER_GITHUB_USER/$(gh api user --jq .login)/" .github/CODEOWNERS && rm -f .github/CODEOWNERS.bak
bash scripts/gh-bootstrap.sh
claude
> /kickoff
```

## The loop

Every coding session runs this protocol (enforced by `CLAUDE.md` and the session-start hook):

1. `pwd` and read the last 5 commits.
2. Run `harness/init.sh`.
3. Run `harness/verify.sh` — must be green.
4. Check active state — `gh issue list --assignee @me` + `gh pr list` (github mode) or top open tasks from `harness/backlog.md` + `gh pr list` (local mode).
5. Read `harness/progress.md` (personal log, not authoritative).
6. Pick **one** open work item (P0 first), no assignee, not an epic.
7. github mode: `gh issue edit <n> --add-assignee @me`, `git checkout -b issue-<n>-<slug>`.
   local mode: flip task `Status: open` → `in-progress`, `git checkout -b task-T-NNN-<slug>`.
8. Pipeline: **product-manager → architect (if cross-cutting) → implementer → tester → reviewer**.
9. Tester ticks `### Acceptance criteria` checkboxes only with evidence (issue comment in github mode, inline checked-box in `backlog.md` in local mode).
10. Push branch, `gh pr create --body "Closes #<n>"` (github mode) or `--body "Refs T-NNN"` (local mode), reviewer approves.
11. `/ship` squash-merges, closes the issue (github mode) or flips task `Status: done` (local mode).
12. Append a dated entry to `harness/progress.md`; push.

The stop hook prevents ending a session while the branch's `verify.sh` is failing or uncommitted changes exist with no open PR.

## Parallel work

Independent work items can be built concurrently in git worktrees:

```
> /parallel 42             # github mode — issue #42
> /parallel task T-007     # local mode  — task T-007
```

In github mode: validates issue #42 is open + unassigned + not an epic, creates `../<repo>-wt-issue-42` on branch `issue-42-<slug>`, and posts a comment on the issue announcing the worktree path.

In local mode: validates task T-007 has `Status: open` + is not `Type: epic`, creates `../<repo>-wt-task-T-007` on branch `task-T-007-<slug>`, and updates the task's `- Worktree:` line in `backlog.md`.

Open a second `claude` session inside the worktree.

When done, from the worktree:

```
> /ship
```

Pushes the branch, opens the PR if missing (with `Closes #42`), and once CI is green and review is approved, squash-merges into `main`.

## Layout

```
.
├── CLAUDE.md                       Harness contract every session reads (mode-aware)
├── .claude/
│   ├── settings.json               Permissions, hooks, env
│   ├── harness-mode.json           Written by /init-mode (per project); chooses github | local
│   ├── commands/                   /start, /init-mode, /kickoff, /next, /parallel,
│   │                               /ship, /status, /retro, /verify
│   ├── agents/                     product-manager, architect, implementer, tester, reviewer, devops
│   ├── skills/                     Shared cross-agent rules (5 skills, ≤ 200 lines each):
│   │                               system-role-boundaries, worktree-management,
│   │                               label-discipline, file-bug, skill-maintenance
│   └── hooks/                      session-start.sh (mode-aware banner), stop.sh
├── harness/
│   ├── init.sh                     Bring up dev env (filled at /kickoff by devops)
│   ├── verify.sh                   End-to-end smoke test (filled at /kickoff)
│   ├── progress.md                 Personal append-only session log (informational)
│   ├── backlog.md                  Local-mode source of truth (T-NNN task blocks); template in github mode
│   └── decisions/                  ADRs — each significant one is also a closed type:spike issue (github mode)
├── docs/
│   ├── spec.md                     YOU fill this in (via /start wizard, or by hand)
│   ├── architecture.md             Maintained by architect agent
│   └── runbook.md                  Ops notes
├── scripts/
│   ├── gh-bootstrap.sh             github mode: sync labels, milestone, Projects v2 board
│   ├── gh-sub-issue.sh             github mode: link child issue under parent epic
│   ├── gh-project.sh               github mode: add-item / set-status / set-field on Projects v2
│   ├── gh-next-issue.sh            github mode: print next P0→P1→P2 open unassigned issue
│   ├── new-worktree.sh             Both modes — `<issue-#>` (github) or `task <T-NNN>` (local)
│   └── merge-worktree.sh           Both modes — handles issue-* and task-T-NNN-* branches
└── .github/
    ├── ISSUE_TEMPLATE/             epic.yml, story.yml, bug.yml, spike.yml, config.yml
    ├── PULL_REQUEST_TEMPLATE.md    Closes #, evidence, checklist
    ├── CODEOWNERS                  Wildcard ownership; expandable for teams
    ├── labels.json                 Declarative label set, synced by gh-bootstrap.sh
    └── workflows/ci.yml            Runs verify.sh — job name `verify` is load-bearing for branch protection
```

## Philosophy

- **Mode is a deployment choice, not a discipline choice.** Both `github` and `local` modes enforce the same agent pipeline, acceptance-criteria discipline, and evidence rules.
- **GitHub is the surface in `github` mode.** Backlog, status, audit trail, decisions, and discussion live on github.com.
- **`harness/backlog.md` is the surface in `local` mode.** Same evidence/acceptance rules; append-only; no remote tracking required.
- **One work item per session.** Forces clean handoffs.
- **Evidence over assertion.** A PR may only merge after `verify.sh` is green AND tester evidence is posted AND `### Acceptance criteria` checkboxes are ticked.
- **The harness is the contract.** Agents must not edit acceptance criteria or remove tests to make things pass.

## License

MIT — see [LICENSE](./LICENSE).
