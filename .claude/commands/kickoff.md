---
description: First-session bootstrap. Mode-aware — seeds GitHub Issues + Projects v2 in github mode, or seeds harness/backlog.md in local mode. Drafts architecture, fills init/verify, enables branch protection if a remote exists.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# /kickoff

You are running the **first session** of a new product built on the engineering-workflow harness. Your job is to bootstrap the project from `docs/spec.md` so every future session has the state it needs.

## Mode detection

```bash
MODE=$(jq -r '.mode // "unset"' .claude/harness-mode.json 2>/dev/null || echo "unset")
if [ "$MODE" = "unset" ]; then
  echo "error: tracking mode is not set. Run /init-mode github|local before /kickoff." >&2
  exit 1
fi
```

If `MODE` is `unset`, stop and require the user to run `/init-mode` first. `/kickoff` is mode-specific — it needs to know whether to file issues or write `backlog.md`.

## Preconditions (both modes)

1. `docs/spec.md` exists and is non-empty. If empty, stop and ask the user to fill it in.
2. **(github mode)** `gh auth status` shows scopes including `project` and `read:org`. If `project` is missing, run `gh auth refresh -s project,read:org` and re-check.
3. A git repo exists at this path (`git rev-parse --is-inside-work-tree`).
4. **(github mode)** A GitHub remote exists (`git remote get-url origin`). If not, stop and tell the user to run `/start` first.

### Idempotency check

**(github mode)**

```bash
PRIOR=$(gh issue list --label meta:bootstrap --state closed --limit 1 --json number --jq '.[0].number // ""')
[ -z "$PRIOR" ] || { echo "Project already kicked off (closed bootstrap issue exists). Ask the user to abort or treat this as an additive update." >&2; exit 1; }
```

**(local mode)**

```bash
[ ! -s harness/backlog.md ] || \
  grep -q '^## T-' harness/backlog.md && {
    echo "Project already kicked off (harness/backlog.md has entries). Ask the user to abort or treat this as an additive update." >&2
    exit 1
  } || true
```

## Steps

### 1. Bootstrap repo state (github mode only)

**(github mode)**

```bash
bash scripts/gh-bootstrap.sh
```

Syncs labels, ensures `v0.1` milestone, creates the Projects v2 board with custom fields, writes `.github/project-config.json`. Idempotent.

**(local mode)** — skip; no GitHub provisioning needed.

### 2. product-manager — seed the backlog

**(github mode)** Dispatch product-manager with:

> Read `docs/spec.md`. File the backlog as GitHub Issues per `.claude/agents/product-manager.md`:
> - 3-6 `type:epic` issues, labeled `area:<n>` and `meta:bootstrap`, in milestone `v0.1`.
> - 15-30 `type:story` issues, labeled `type:story`, `priority:P0|P1|P2`, `area:<n>`, in milestone `v0.1`. Canonical schema body with `### Acceptance criteria`.
> - `scripts/gh-sub-issue.sh <epic#> <story#>` for each story.
> - `scripts/gh-project.sh add-item <story#>` for each story.

**(local mode)** Dispatch product-manager with:

> Read `docs/spec.md`. Seed `harness/backlog.md` per the canonical task-block schema in CLAUDE.md:
> - 3-6 `Type: epic` tasks, one per major capability cluster, each with `Area: <n>` and `Priority: P0|P1|P2`.
> - 15-30 `Type: story` tasks linked to their parent epic via `Parent: T-NNN`.
> - T-NNN IDs zero-padded sequential starting at T-001. Append-only.

### 3. architect — draft architecture

Dispatch architect (both modes):

> Read `docs/spec.md` and the seeded work items. Draft `docs/architecture.md` covering stack, modules, data model, dependencies, cross-cutting concerns. Record the stack as `harness/decisions/0001-stack.md`. **(github mode)** also file a closed `type:spike` + `meta:bootstrap` issue linking to the ADR. **(local mode)** append a `Type: spike, Status: done` task to `harness/backlog.md` linking to the ADR.

### 4. devops — fill init.sh / verify.sh / CI

Dispatch devops (both modes):

> Read `docs/architecture.md` for the stack. Fill `harness/init.sh` (idempotent bring-up) and `harness/verify.sh` (real end-to-end smoke). Write `.github/workflows/ci.yml` — **job name must be `verify`** (branch protection at step 9 requires that name).
> **(github mode)** Also extend `.github/labels.json` with any `area:*` entries needed and re-run `scripts/gh-bootstrap.sh`.

### 5. Verify the baseline (both modes)

```bash
bash harness/init.sh
bash harness/verify.sh
```

Must exit 0. If not, return to devops.

### 6. Append kickoff entry to progress.md (both modes)

```
## <YYYY-MM-DD HH:MM> — kickoff
- Mode: <github | local>
- Spec: docs/spec.md
- Epics filed: <N>
- Stories filed: <N> (P0: <a>, P1: <b>, P2: <c>)
- Architecture: <one-line stack summary>
- ADR 0001: <stack rationale>
- Bootstrap audit: <N> closed spike issues (github) | N spike tasks (local)
```

### 7. Commit and push

```bash
git add -A
git commit -m "Kickoff: seed backlog, architecture, harness scripts"
```

If a remote exists:

```bash
git push -u origin main
```

### 8. Watch the first CI run (only if remote + workflow exist)

```bash
if [ -f .github/workflows/ci.yml ] && git remote get-url origin >/dev/null 2>&1; then
  sleep 5
  RUN_ID=$(gh run list --branch main --workflow ci.yml --limit 1 --json databaseId --jq '.[0].databaseId')
  gh run watch "$RUN_ID" --exit-status
fi
```

If CI fails, stop. Fix the baseline (devops), commit, push, re-watch. Do not enable branch protection until CI is green at least once.

### 9. Configure merge style and enable branch protection (only if remote exists)

```bash
REPO_NWO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

gh api --method PATCH "repos/$REPO_NWO" \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F allow_squash_merge=true \
  -F delete_branch_on_merge=true >/dev/null

gh api --method PUT "repos/$REPO_NWO/branches/main/protection" \
  --input - <<'EOF'
{
  "required_status_checks": { "strict": true, "contexts": ["verify"] },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

### 10. Report

Print:

```
✓ Kickoff complete.
  Mode:          <github | local>
  Repo:          <gh repo url, if remote>
  Project:       <project url, github mode only>
  Milestone:     v0.1 (github mode only)
  Epics filed:   <N>
  Stories filed: <N> (P0: <a>, P1: <b>, P2: <c>)
  CI:            green on main (if remote)
  Protection:    enabled (requires `verify` check, if remote)
  Merge style:   squash, delete branch on merge (if remote)

Next:
  /status                 see the backlog
  /next                   pick the top P0 and start building
  /parallel <id>          work on an item in an isolated worktree
```

## Failure handling

- If any subagent fails, do **not** push partially. Leave commits local, surface the error.
- If CI fails on first run, fix the cause (typically a devops issue) and re-push.
- If branch protection fails to apply (auth scope, permissions), surface the error. The harness still works without protection.
- **(local mode)** If there's no remote, steps 8-9 are skipped automatically. The local backlog + tests are still functional.
