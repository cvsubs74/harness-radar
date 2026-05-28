---
name: worktree-management
description: Canonical protocol for git worktree creation, use, and cleanup. One task per worktree. Never edit in the primary repo path during parallel work. Applies in both github and local tracking modes.
---

# Worktree management

The harness uses `git worktree` to isolate parallel work. Each task that runs concurrently with others gets its own worktree on its own branch.

## Why worktrees (not multiple clones)

- One `.git/` directory, many checked-out trees — fast switching, low disk cost.
- Each worktree has its own branch checkout; no risk of contaminating another session's branch.
- Branches stay local to the worktree; cleanup is one `git worktree remove` call.

## The contract

- **One task per worktree.** A worktree is named after the task it serves: `<repo>-wt-issue-<n>` (GitHub mode) or `<repo>-wt-task-T-NNN` (local mode).
- **Never edit in the primary repo path** while a worktree session is active on a parallel task. The primary path is for the lead session; worktrees are for parallel work.
- **Never reuse another session's worktree.** Even if it's idle. Cleanup it first, then create yours.
- **Worktrees live as siblings of the primary repo**, not inside it. The harness writes them to `../<repo>-wt-*` by default. Some teams use `.worktrees/<task-id>` inside the repo path; both work — match what the project's `scripts/new-worktree.sh` does.

## Creating a worktree

Always use the harness script:

```bash
# GitHub mode
bash scripts/new-worktree.sh <issue-number>

# Local mode (when implemented)
bash scripts/new-worktree.sh task T-NNN
```

The script:

1. Validates the task is OPEN, unassigned, and not an epic (GitHub mode) or has `Status: open` (local mode).
2. Derives a slug from the title.
3. Runs `git worktree add <path> -b <branch> origin/main`.
4. Records the worktree path on the task (GitHub: comments on the issue; local: updates the `Worktree:` line in `backlog.md`).

Don't hand-roll `git worktree add` — the script's bookkeeping is load-bearing for parallel session coordination.

## Using a worktree

```bash
cd ../<repo>-wt-<id>
```

Inside the worktree:

- `pwd` to confirm you're in the right place.
- `git branch --show-current` to confirm the branch.
- `git log --oneline -5` to see the baseline.
- Then run `harness/init.sh` + `harness/verify.sh` — every session, every worktree.

Treat the worktree as a normal git checkout. Commits, branches, and `gh` commands all work the same.

## Shipping from a worktree

`/ship` from inside the worktree:

1. Pushes the branch to `origin`.
2. Opens the PR (if not already open) with `Closes #N` (GitHub mode) or `Refs T-NNN` (local mode).
3. After CI is green and reviewer approves, squash-merges.
4. Tears down the worktree:
   ```bash
   git worktree remove <path>
   git branch -d <branch-name>
   ```
5. In local mode, also flips the task to `Status: done` in `harness/backlog.md`.

If `/ship` fails partway, the cleanup step is the recoverable part — re-run `git worktree remove` manually.

## Cleanup discipline

A worktree past its task is debt. The harness's `session-start.sh` hook scans `git worktree list` and warns about worktrees on merged branches.

Manual cleanup (if `/ship` was bypassed):

```bash
# From the primary repo path
git worktree list                          # see what's outstanding
git worktree remove ../<repo>-wt-<id>      # remove the worktree
git branch -d <branch-name>                # delete the local branch
```

If the worktree has uncommitted changes you don't want to lose:

```bash
git worktree remove --force ...    # discards working tree
# OR
git stash                          # save changes first
git worktree remove ...            # then remove
```

The harness will not auto-`--force` a removal. If you see "worktree has uncommitted changes" — investigate first; the user may have in-flight work.

## Hard rules

- **Never run `rm -rf` on a worktree directory** — that leaves `git worktree list` in a corrupted state. Always `git worktree remove`.
- **Never push from the primary repo path on behalf of a worktree branch.** Each session pushes from its own worktree.
- **Don't share worktrees between sessions.** Two Claudes on the same worktree will clobber each other.
- **The primary repo path is for the lead session and for `/kickoff` / `/status` / `/init-mode` operations.** Task execution happens in worktrees.
