# Progress log

Personal session log. Normally append-only; explicitly reorganized 2026-05-27 23:10 at user request to group topically within chronological order and to tighten verbose entries. Future sessions resume append-only.

Events: `kickoff`, `#N <title>` (build session), `shipped #N`, `retro #N`, `note`.

---

## 2026-05-26 19:02 — note
- Discussion-only session: assessed whether the engineering-workflow harness scales to complex products. Discipline (AC, ADRs, agent pipeline, append-only log) ports; specific tooling (features.json SoT, one-feature-per-session, worktree parallelism) is sized for solo/small teams.

## 2026-05-26 21:30 — note
- Harness rewrite to GitHub-first SoT shipped in 8 commits (c7b707b → 5c09f91). Plan: ~/.claude/plans/toasty-cooking-treehouse.md. Outstanding: `.claude/settings.json` needs 4 manual permits for `scripts/gh-*.sh`.

## 2026-05-27 18:05 — kickoff
- Mode: github (cvsubs74/harness-radar, public). Spec: local CLI reading `gh` + `harness/progress.md`, emits velocity + harness-discipline report.
- Backlog: 5 epics (#1-#5) + 21 stories (8 P0 / 10 P1 / 3 P2, #6-#26), all on project #2 / milestone v0.1.
- Stack: Python 3.11+ CLI, pipx-installed, stdlib sqlite3, `subprocess(gh)` + jinja2. ADR-0001 + closed spike #27 record the trade-off vs Node and Go.
- Baseline init.sh + verify.sh green (ruff + 1 smoke pytest).

## 2026-05-27 18:25 — #6 Add CLI entrypoint and --help
- PM added 5th AC for the no-args→help case (Summary promised it; argparse default would silently no-op).
- Implementer: stdlib argparse, custom formatter for `Usage:` casing, explicit no-args short-circuit. 1 commit (2bb544e), 6/6 pytest.
- PR #30, CI green. Tester evidence + reviewer comment on issue.
- Baseline fixes mid-session (direct to main): 85ae1a5 capped `gh-project.sh items(first:200)` → 100 (bug #28 filed for proper pagination). Board Status options corrected via GraphQL `updateProjectV2Field` (bug #29 for `gh-bootstrap.sh` to handle existing system fields).

## 2026-05-27 18:31 — shipped #6
- PR #30 squash-merged as 81312f9. Issue auto-closed; board → Done.

## 2026-05-27 18:34 — retro #6
- **Worked**: pipeline ran clean; PM caught the no-args gap before impl; direct-to-main baseline commits kept the feature PR uncontaminated.
- **Didn't**: kickoff "succeeded" without exercising `gh-project.sh` — #28/#29 only surfaced on first /next; self-review can't formally `--approve` (reviewer fell back to `--comment`).
- **Surprises**: Projects v2 GraphQL `items` capped at 100; `Status` is an undeletable system field, only mutable via `updateProjectV2Field`; `gh project create` auto-creates Status with GitHub defaults, defeating the bootstrap script's "create if missing" idempotency.
- **Follow-ups**: #28, #29, new #31 (P2 — /kickoff should smoke-test gh-project.sh transitions).
- **Memory**: saved `gh-projects-v2-quirks.md`.
- **Addendum (recorded 23:03, posted as #6 comment 4561148047)**: pattern visible only after 2 ships — /next's `log(#N)` commit on main puts the open PR behind under strict-mode protection, forcing the next /ship to rebase + force-push + CI re-run (~30s). Three dissolves: move log into the squash commit, defer log to /ship, or accept the friction. Per user, not filing as a separate issue.

## 2026-05-27 22:27 — #7 Validate target repo is a github-mode harness repo
- PM 3-way canonicalization: reworded AC4 (collector doesn't exist yet → exit 0 + no stderr error + placeholder OK); added 5th AC for `.claude` present but `harness/init.sh` missing; Notes pin the positional `repo` arg.
- Implementer: extracted `validate_repo(path) -> None` raising typed `RepoValidationError`; CLI exits 1 (distinct from argparse's 2). Placeholder `(collector not yet implemented)` on stdout for valid repos. 1 commit (706e49a); pytest 6 → 18. Composes cleanly with #6's no-args short-circuit.
- PR #32, CI green twice. Tester evidence + reviewer comment on issue.

## 2026-05-27 22:32 — shipped #7
- PR #32 squash-merged as 33b017f. Branch needed rebase + force-with-lease before merge to satisfy strict-mode (CI re-ran 21s) — the same pattern called out in #6's addendum. Issue auto-closed; board → Done.

## 2026-05-27 23:09 — retro #7
- **Worked**: PM canonicalized three real ambiguities upfront; implementer designed for future use by extracting `validate_repo` as a pure public seam for the not-yet-existent collector; suite grew 6 → 18 with healthy unit/e2e split, verify still 0.73s.
- **Didn't**: rebase-before-merge friction again (captured in #6 addendum).
- **Surprises**: implementer voluntarily added edge-case tests beyond AC (malformed JSON, missing `mode` key, non-dict JSON, unknown mode); reviewer probed all, all held. `nargs="?"` composes with the no-args short-circuit because the short-circuit runs before `parse_args`.
- **Follow-ups**: none.
- **Memory**: none.

## 2026-05-27 23:53 — #10 Pull all repo issues with metadata
- PM: 5-way canonicalization — fixed AC1's broken `wc -l` (header line off-by-one), added Non-goal bounding to ≤1000 issues, pinned dataclasses in Notes, tightened AC3 (source + defensive PR filter) and AC4 (count match + #1 present). Wrote ADR-0002 alongside (slightly stretches the ADR convention; reviewer noted as non-blocking).
- Implementer: new `harness_radar.collector` package (`__init__.py` public API + `gh.py` private shelling). `IssueRecord` is `@dataclass(frozen=True)` with `tuple[str, ...]` for labels/assignees, 10 fields per AC2. CLI wired — placeholder from #7 is gone; valid repos now print `Collected N issues from <slug>`. 17 new tests (35 total), all edge cases (gh missing, malformed JSON, SSH remote, snake_case `pull_request` key, non-GitHub remote) covered. 1 commit (8b06777).
- Tester evidence: posted on #10 (comment 4561457850); 3-axis count agreement (gh CLI = harness-radar CLI = Python API = 30). All 4 AC ticked.
- Reviewer round 1: REQUEST_CHANGES — CI red because the new CLI dogfood test calls real `gh issue list` but the workflow's `GH_TOKEN` was scoped only to `init` step, not `verify`.
- CI fix (committed on feature branch, not main — avoids the rebase-friction pattern from #6/#7): 6a44ccc hoisted `GH_TOKEN` to job-level `env`, added explicit `permissions: issues: read` at workflow top-level.
- Reviewer round 2: APPROVE. CI green in 20s.
- PR: #33 — 2 commits (impl + ci fix); both CI green.

## 2026-05-27 23:58 — shipped #10
- PR #33 squash-merged as 2b10114. Branch rebased onto main before merge (the log(#10) commit on main put it behind, same pattern as #6/#7); single force-with-lease push, CI re-ran 23s, then merge.
- Tracking: issue #10 auto-closed by `Closes #10`; project board → Done.

## 2026-05-28 09:47 — #11 Pull issue body edit history via userContentEdits
- PM: 5-way canonicalization — pinned AC2 to `diff` (dropped before/after option), pinned `editor: str | None`, pinned lazy-fetch via NEW `collect_edits(repo_slug, issue_number)` function (NOT a field on `IssueRecord`), pinned `gh api graphql` envelope, pinned fixture strategy (mocks + 1 live integration vs issue #6). Followed the no-ADR-this-time instruction; rationale lives in issue Notes per #10's retro lesson.
- Implementer: new `EditRecord` frozen dataclass + `collect_edits()` function in `collector/gh.py`, re-exported via `__init__.py`. `IssueRecord` and `collect_issues` byte-identical (reviewer confirmed). Defensive sort by `edited_at` rather than trusting API order (live API returns newest-first). 1 commit (7360dc7); pytest 35 → 46.
- Tester evidence: posted on #11 (comment 4566270915). Explicitly verified integration test ran (not skipped) — the lesson from #10's retro landed. Independent GraphQL probe gave count=3 for issue #6, matching Python API. All 4 AC ticked.
- Reviewer: APPROVE, CI green. Two non-blocking nits flagged (a docstring typo `doesn't paid → doesn't pay`, and a missing inline comment about `gh issue view --json userContentEdits` not working). Could fold into a follow-up commit or punt to next collector PR.
- Discovery worth flagging: `gh issue view --json userContentEdits` returns "Unknown JSON field" — the GraphQL endpoint is the ONLY path. The implementer verified live before relying on it.
- PR: #34 — CI green.

## 2026-05-27 23:57 — retro #10
- **Worked**: PM did substantive 5-way canonicalization including catching the broken `wc -l` baseline (would've been untestable); implementer designed the collector as a *package* not a module, anticipating PR-cycle / body-edit-history stories — same forward-thinking pattern as #7's `validate_repo` seam; reviewer's `gh pr checks --required` discipline caught a CI-only failure that tester missed (first multi-round review of the session, harness handled it cleanly).
- **Didn't**: tester ran `verify.sh` locally (passed because local has `gh` auth) but didn't think to check `gh pr checks` for CI status — a real blind spot when tests exercise external state. Worth strengthening the tester prompt for collector/CI-touching stories. Rebase friction hit a third time, same dissolves available in #6 addendum.
- **Surprises**: putting the CI fix on the *feature branch* instead of main (deliberate choice this session) actually paid off — main stayed unchanged during the impl→review round trip, so /ship's rebase only had to absorb the pre-existing `log(#10)` commit, not also a baseline CI patch. Small architectural win. Also: default `GITHUB_TOKEN` permissions in workflows are repo-dependent — `gh auth status` passes but `gh issue list` returns exit 4 without an explicit `permissions: issues: read` declaration.
- **Follow-ups**: none filed. The PM-writes-ADR convention (ADR-0002 was per-issue canonicalization rationale, not architectural) is a small process question that can resolve organically rather than tracked as a story; if PM keeps doing it for the next 2-3 stories, file then.
- **Memory candidates**: saved `gh-actions-token-quirks.md` capturing the GH_TOKEN + permissions distinction; MEMORY.md now indexes both this and `gh-projects-v2-quirks.md`. These two cover most external-GitHub-API gotchas a harness-using project will hit.
