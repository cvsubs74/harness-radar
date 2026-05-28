# 0002 — Issue #10 ("Pull all repo issues with metadata") interpretation

**Status:** accepted
**Date:** 2026-05-27
**Related issue:** #10
**Mode:** auto (no user available — product-manager agent re-canonicalization)

## Context

Issue #10 is the spine of the `area:collector` work — the first story that the
implementer will turn into real code under `src/harness_radar/collector/`. As
filed, four of its acceptance criteria had ambiguity that would have made the
tester's job indeterminate or invited scope creep. Per the product-manager
contract (`.claude/agents/product-manager.md`), when ambiguity is found during
`/next` and no user is reachable, the agent picks the most defensible
interpretation, updates the issue body, and records the decision in an ADR.

This ADR captures the five interpretive calls made on a single edit of issue
#10 so future readers (and the tester) can see *why* the bullets read the way
they do.

## Decisions

### 1. AC1 — replace the broken `wc -l` baseline

**Original:** count of collector records must equal
`gh issue list --repo <r> --state all --limit 1000 | wc -l`.

**Problem:** `gh issue list` in default table mode prints a header line, so
`wc -l` returns `N + 1`. The criterion is untestable as written.

**Resolution:** use the JSON path which returns a clean integer:

```
gh issue list --repo <r> --state all --search 'is:issue' --limit 1000 \
  --json number --jq 'length'
```

The `--search 'is:issue'` clause filters out pull requests at the source so
the baseline matches the intent of AC3. AC1 now reads as an integer-equality
check, not a line-count check.

### 2. >1000 issues is a non-goal in v0.1

The architecture doc commits the collector to "sequential, not parallel" paging
(issue #13). It does not commit to handling repos with >1000 issues, and the
`--limit 1000` cap in AC1 implicitly bounds scope to that size. Rather than
leave this silent (option `c` — invites scope creep or undocumented limitation)
or expand AC to require full pagination (option `b` — larger scope than the
story can carry), we add an explicit non-goal:

> Repos with >1000 issues; pagination beyond `--limit 1000` is a separate
> story to be filed if a real user hits the cap.

This bounds the implementer's scope cleanly. The dogfooded repo
(`cvsubs74/harness-radar`) has ~30 issues, so the cap is comfortable for v0.1.

### 3. Issue records are Python `dataclass`es

The architecture doc says "typed dataclasses" in the `collector/` module row
but doesn't pin it inside the story. Without a pin, the implementer could
reach for `pydantic`, `attrs`, or `TypedDict` — any of which would add a
third-party dep (ADR-0001 explicitly limits runtime deps to `jinja2`) or
under-specify the contract (`TypedDict` doesn't enforce at runtime).

A one-line Notes addition pins the call:

> Implementer uses Python `dataclasses` for issue records; no third-party
> schema library (pydantic, attrs, etc.) per ADR-0001.

### 4. AC3 — concrete filter check for PR exclusion

**Original:** "Pull-request entries returned by the issues endpoint are
excluded from the issue list."

**Problem:** intent is right but the test mechanism is implicit. `gh issue
list` includes PRs by default because GitHub's REST `/issues` endpoint does.
The tester needs a concrete assertion.

**Resolution:** rewrite AC3 to specify both the source-side filter and the
result-side assertion:

> Collector uses `gh issue list --search 'is:issue' ...` (or equivalent
> filter) so pull-request entries are excluded at the source; for every
> record returned, no `pullRequest` / `pull_request` key appears in the
> underlying payload.

This is grep-able and gives the tester a one-line check.

### 5. AC4 — exact count + presence of a known issue

**Original:** "Collector runs successfully against this repo and returns at
least the epics filed during kickoff."

**Problem:** "at least the epics" is weak. The collector must return *every*
issue, not just the epics. A test that only checks for epics would silently
pass even if the collector dropped 80% of the rows.

**Resolution:** two-axis tightening:

> Against `cvsubs74/harness-radar`, the count of returned records equals
> the integer from the AC1 command, AND issue #1 (the parent epic for
> collector work) is present in the result.

Count-equality catches "we dropped some records," presence-of-#1 catches "we
returned the count but it's the wrong rows" (e.g., a bug where the collector
silently swaps repos).

## Consequences

- Tester for issue #10 has five unambiguous, mechanically-verifiable bullets.
- Implementer has a hard pin on `dataclasses` (no creeping in pydantic) and a
  clear scope bound (≤1000 issues for v0.1).
- A future `/next` session that needs to break the 1000-issue cap files a new
  story with `area:collector` rather than re-litigating #10's AC.
- The PR closing #10 will need a tester comment that quotes the AC1 integer
  it observed; that's normal tester evidence discipline, surfaced here only
  because the integer baseline is new.
