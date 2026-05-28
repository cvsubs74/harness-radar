# 0001 — Stack selection for harness-radar

**Status:** accepted
**Date:** 2026-05-27
**Related issue:** #27

## Context

harness-radar is a local CLI that reads GitHub Issues / Projects v2 data via the `gh` CLI (plus raw GraphQL for `userContentEdits`) and emits a markdown / HTML velocity + harness-discipline report. The spec is explicit: single-command install, no hosted DB, SQLite cache acceptable, no heavy frameworks, "Python or Node — pick what makes shelling `gh` and templating markdown cheap." With 21 stories in the seeded backlog and a 60-second cold-start budget (issue #26), the stack must be decided once and stop being re-litigated.

## Decision

We will build harness-radar in **Python 3.11+**, distributed as a `pyproject.toml`-based package installed via `pipx install .`. Runtime deps are `jinja2` (templating) and the `gh` CLI binary on the user's PATH. Cache is stdlib `sqlite3`. CLI is stdlib `argparse`. Tests are `pytest`. Dev workflow uses `uv`.

## Alternatives considered

- **Node 20+ / TypeScript** with `execa`, `@octokit/graphql`, `better-sqlite3`, `vitest`, single-file binary via `pkg`/`bun` — nicer `npx harness-radar` UX and a richer GitHub-tooling ecosystem, but drags in a native-build SQLite binding (breaks the 60-second cold-install budget on some clean machines) and bypasses `gh`'s auth/rate-limit handling when calling `@octokit` directly. The marginal install-UX win doesn't outweigh those costs for a CLI whose primary user already has `gh` installed.
- **Go** — single static binary is genuinely attractive for install simplicity, but markdown templating, diff prose, and percentile math are noticeably more verbose, and the contributor pool that touches harness-adjacent tooling is Python/TS-leaning. Overkill for a 21-story MVP.
- **Pure shell + jq** — appealing for "no framework" purity but the AC-diff detection and percentile aggregation push past what's pleasant to maintain in bash; rejected immediately.

## Consequences

**Affordances unlocked.**
- Stdlib `sqlite3` and `json` mean the cache module ships with zero new runtime deps.
- `subprocess.run(["gh", "api", "graphql", "-f", f"query={q}"])` is one line and inherits `gh`'s auth, rate-limit headers, and pagination cursors — no Octokit client to maintain.
- `jinja2` templates make the markdown and HTML renderers share most of their layout logic.
- `pipx install .` is a single command and satisfies issue #9 directly.
- Implementer can write pure functions in `metrics/` and unit-test them without mocking I/O.

**Constraints accepted.**
- Users without Python 3.11+ on PATH need to install it (mitigation: `pipx` works on any system Python ≥ 3.8, and `pipx` itself is one `brew install` or `apt install`).
- We commit to the `gh` CLI version floor (≥ 2.40) and to never bypassing it for direct HTTP calls — if a future feature requires a GraphQL field `gh` can't surface, that's a fresh ADR, not a hidden Octokit import.
- No single-static-binary distribution in v0.1. If install ergonomics become a real complaint, we can revisit with a `pex` or `shiv` ADR without changing the source.
- All template strings live in `.j2` files under `src/harness_radar/report/templates/` — the tester needs to know that to locate the load-bearing section headings (`## Lead time`, etc.) referenced in issues #20 and #23.
