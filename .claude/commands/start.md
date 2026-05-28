---
description: New-product wizard — detach from boilerplate, fill in spec.md, create GitHub repo + project, run /kickoff
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, AskUserQuestion
---

# /start

You are running the **new-product wizard**. The user just cloned `engineering-workflow` into a fresh directory and ran Claude here. Your job is to walk them from "empty boilerplate" to "first issue ready to build" with GitHub clearly central — repo, labels, milestone, project board, branch protection.

Be conversational. Ask one (or at most two related) questions per turn. The user is likely not a power user — don't dump JSON in their face; summarize.

---

## Step 1 — Preflight

Run silently before asking anything:

```bash
pwd
command -v gh >/dev/null || echo "MISSING: gh"
command -v jq >/dev/null || echo "MISSING: jq"
gh --version | head -n1
gh auth status 2>&1 | head -n 20
git rev-parse --is-inside-work-tree 2>/dev/null && echo "git: yes" || echo "git: no"
git remote get-url origin 2>/dev/null || echo "no remote"
git log --oneline -3 2>/dev/null || echo "no commits"
test -f docs/spec.md && wc -l docs/spec.md || echo "no spec"
```

### Gate: GitHub CLI is mandatory

- If `gh` is missing: stop. Tell the user to install with `brew install gh` (or platform equivalent) and re-run.
- If `gh` version < 2.49: stop. Tell the user to `brew upgrade gh` (sub-issues API requires 2.49+).
- If `gh auth status` shows not logged in: stop. Tell the user to run `gh auth login` and re-run.
- If logged in but `project` scope is missing: run `gh auth refresh -s project,read:org` and re-check.

### State classification

- **A. Fresh clone of boilerplate** — `.git` exists, `origin` is `…cvsubs74/engineering-workflow…` (or empty), no kickoff. Most common case. Proceed.
- **B. Already kicked off** — kickoff issues exist on GitHub (`gh issue list --label meta:bootstrap --state closed --limit 1`). Stop: tell the user to use `/status`, `/next`, or edit `docs/spec.md` and re-run `/kickoff`.
- **C. Wizard already ran but no kickoff** — `docs/spec.md` has user content AND no `meta:bootstrap` issues yet. Ask: review & skip to kickoff / restart wizard / cancel.
- **D. No git at all** — `.git` missing. Skip the detach step; plan to `git init` later.

Print a single-sentence state summary, then ask the wizard questions.

---

## Step 2 — Detach from the boilerplate (only for state A)

If `origin` points at the engineering-workflow repo, ask:

> This directory still tracks the boilerplate as `origin`. I'll detach git so your work isn't tied to it. OK to run `rm -rf .git && git init -b main`?

If yes:

```bash
rm -rf .git
git init -b main
```

If no: stop and tell the user to detach manually before re-running `/start`.

---

## Step 3 — Spec wizard (conversational Q&A)

> I'll ask 8 short questions to draft `docs/spec.md`. Skip any with "skip" — we can fill them in later.

Ask one or two at a time. Hold answers in context; don't write to disk until step 4.

1. **Product name** — short, lowercase, kebab-case. (e.g. `expense-wise`.)
2. **One-line pitch** — what it does and for whom.
3. **Why does this exist?** 1-3 sentences.
4. **Who are the primary users?** 1-3 sentences.
5. **Top 3-7 user flows.** Step-by-step bullets are fine.
6. **MVP must-haves.** Push back if the list is huge — 5-10 items, not 30.
7. **Nice-to-haves and out-of-scope.**
8. **Stack preferences and constraints?** (Optional.) If none, the architect decides.

Then:

> One last thing — what does success look like for the MVP?

---

## Step 4 — Draft and confirm `docs/spec.md`

Write `docs/spec.md` from the answers, then show the user the rendered file and ask:

> Here's `docs/spec.md`. Does this capture it? Options: "looks good" / "edit X to say Y" / "restart" / "save and stop".

Loop until approved.

---

## Step 5 — Create the GitHub repo

This is **not optional**. The harness requires a GitHub repo to host issues, the project board, and CI.

1. **Account/org**: default to `gh api user --jq .login`.
   > Create under your account `<default>` or a different org? (press enter for default)
2. **Repo name**: default to `$(basename "$PWD")`.
3. **Visibility**: use `AskUserQuestion` with Private (recommended) and Public. Do not default to Public.

Create the repo (no push yet):

```bash
gh repo create <owner>/<name> --<visibility> --source=. --remote=origin --description "<one-line pitch>"
```

---

## Step 6 — Personalize CODEOWNERS

Replace the placeholder in `.github/CODEOWNERS`:

```bash
GH_USER=$(gh api user --jq .login)
sed -i.bak "s/PLACEHOLDER_GITHUB_USER/$GH_USER/" .github/CODEOWNERS
rm -f .github/CODEOWNERS.bak
```

---

## Step 7 — Initial commit + push

```bash
git add -A
git commit -m "Initial commit: <product-name> from engineering-workflow boilerplate"
git push -u origin main
```

---

## Step 8 — Bootstrap GitHub state (labels, milestone, project board)

```bash
bash scripts/gh-bootstrap.sh
git add .github/project-config.json
git commit -m "Bootstrap: labels, milestone v0.1, Projects v2 board"
git push
```

If the script errors on scopes, run `gh auth refresh -s project,read:org` and re-try.

---

## Step 9 — Hand off to `/kickoff`

Tell the user:

> Spec saved, repo created, GitHub state bootstrapped. Running `/kickoff` next — it dispatches the product-manager (files issues), architect (picks the stack, writes ADR-0001), and devops (fills init.sh/verify.sh/CI). Then it pushes, watches the first CI run, and enables branch protection. Takes 3-6 minutes.

Then execute the `/kickoff` flow described in `.claude/commands/kickoff.md`. Do not re-implement it — invoke its steps in order.

---

## Step 10 — Next-steps banner

```
✓ Project bootstrapped: <product-name>
  Repo:          <gh repo url>
  Project board: <project url>
  Stack:         <chosen stack>
  Stories filed: <N> (P0: <a>, P1: <b>, P2: <c>)
  Protection:    enabled on main (requires `verify` check)

What's next:
  /status                see the backlog
  /next                  build the highest-priority P0
  /parallel <issue-#>    spin off concurrent work in a worktree
  /verify                sanity-check the dev environment

When in doubt, read CLAUDE.md.
```

---

## Hard rules for the wizard

- **Don't write `docs/spec.md` until step 4** — keep answers in chat until approved.
- **Don't create the GitHub repo as public by default.** Always ask.
- **Don't proceed without GitHub.** Hybrid local-only mode isn't supported — abort with a clear message if the user declines repo creation.
- **Don't push before the user confirmed the spec.**
- **Don't skip `/kickoff`.** If the user wants to do kickoff later, that's OK — but tell them the project isn't usable until kickoff runs.
- **If interrupted**, the user re-runs `/start` — step 1's state detection picks up where things left off.
