---
name: skill-maintenance
description: How to add, edit, or retire a shared skill or an agent contract file in the engineering-workflow harness. Enforces the agent-doc-PR pattern, the line-cap discipline, and audit-trail requirements so the harness stays lean.
---

# Skill maintenance

Skills and agent contracts are the harness's load-bearing prose. They override the default Claude system prompt in this repo. Edit carelessly and you change how every future session behaves. This skill governs how to edit safely.

## When to add a skill

Add a skill when **all** of the following are true:

1. The same multi-step procedure shows up in two or more agent contracts, **or** the same procedure has been re-invented across two or more sessions.
2. The procedure has a checklist or rulebook (not just a single command).
3. Drift on this procedure would actively break the harness (silent failures, wrong labels, lost work).

If only (1) is true but the procedure is a single shell incantation, it belongs in `scripts/` instead. If the procedure is project-specific (not portable across harness installs), it belongs in `docs/playbooks/<agent>.md`, not in `.claude/skills/`.

The lean engineering-workflow setup defaults to **five skills**:

- `system-role-boundaries` — who owns what
- `worktree-management` — git worktree protocol
- `label-discipline` — github-mode label table
- `file-bug` — bug-report protocol
- `skill-maintenance` — this file

Resist adding more. Each new skill is a thing that has to stay current.

## When to edit an existing skill

Edit when:

- A rule changed (e.g. a label was added or renamed).
- A procedure was found ambiguous in practice and needs disambiguation.
- A new mode (e.g. local) needs to be reflected in a mode-aware skill.

**Don't** edit a skill to add an example for a one-off case. Examples are for the common path. Edge cases go in the agent that hit them, or in `docs/playbooks/<agent>.md`.

## Line cap

Every skill ≤ 200 lines (including frontmatter). If a skill grows past that, split it or prune.

Why: skills are loaded into Claude's context on demand. Long skills are skim-resistant and they bloat the active surface. The discipline keeps the library auditable.

If you're at 180 lines and considering a "minor" addition — stop. Find what to remove first.

## The agent-doc-PR pattern

Edits to `.claude/skills/*/SKILL.md` and `.claude/agents/*.md` go through a **separate PR** from product / feature work. Reasons:

- These files change agent behavior. Bundling them with feature code makes both harder to review.
- A targeted PR has a small diff that reviewers can actually read line-by-line.
- Reverts are surgical.

Branch naming for a skill/agent edit:

```
docs/skill-<skill-name>-<short-reason>
docs/agent-<agent-name>-<short-reason>
```

Examples:

- `docs/skill-label-discipline-add-priority-p3`
- `docs/agent-tester-clarify-flaky-rule`

Commit message format:

```
docs(skills): <skill-name> — <what changed and why>

<2-3 sentences on motivation and any backward-compat note>
```

PR body must include:

- **What changed** — one sentence.
- **Why** — the trigger (a session that hit ambiguity, a label that drifted, a new mode).
- **Migration** — if anything downstream needs to update (rare).

## Frontmatter discipline

Every `SKILL.md` starts with YAML frontmatter:

```yaml
---
name: <kebab-case-slug>
description: <one-sentence trigger description for when this skill applies>
---
```

The `description` is what Claude uses to decide whether to invoke the skill on a given turn. It should:

- Name the user-visible trigger ("when filing a bug", "before creating a worktree").
- Be specific. "General guidance" is not a description.
- Mention mode if mode-sensitive ("GITHUB MODE ONLY").

Agent files (`.claude/agents/*.md`) also have frontmatter with `name`, `description`, and `tools`. Don't add fields the harness doesn't read.

## Retiring a skill

Skills go stale. When a procedure is no longer load-bearing (e.g. an enforcement hook now does what the skill warned about):

1. Open a `docs/skill-<name>-retire` PR.
2. `git mv` the file to `.claude/skills/_archive/<name>/SKILL.md` and prepend a `**RETIRED:**` line at the top with the date and reason.
3. Grep for references in agent contracts, CLAUDE.md, and other skills; update or remove.
4. Commit message: `docs(skills): retire <name> — <reason>`.

Don't just delete. The archive is a paper trail for "why isn't this a skill anymore."

## Audit trail

`git log -- .claude/skills/<name>/SKILL.md` should tell a coherent story of how the skill evolved. To keep it coherent:

- One PR = one logical change to the skill. Don't bundle three unrelated edits.
- Commit messages reference the trigger (PR number that surfaced the gap, or `harness/decisions/NNNN-*.md` ADR if the change came from a decision).
- The `name` and `description` frontmatter stay accurate — update them when the body changes.

## Hard rules

- **Don't edit a skill to fit a single feature.** Skills are cross-cutting. If only one feature needs a rule, document it on the feature, not in a skill.
- **Don't add a skill in the same PR as feature code.** Separate PR, per the agent-doc-PR pattern.
- **Don't grow past 200 lines.** Split or prune.
- **Don't leave a skill stale.** If the body lies about current behavior, fix or retire it — silence is worse than absence.
