# Product spec — harness-radar

## What we're building

A local CLI that points at any repo using the engineering-workflow harness and emits
a velocity + health report. Run `harness-radar <repo>` (or `--all` over a directory of
repos) and get a markdown / HTML view of: lead time per issue, agent-pipeline
bottlenecks, and a "smell detector" for the harness's hard rule that acceptance
criteria must not be re-edited to make checks pass.

The data source is what the harness already produces — GitHub Issues + Projects v2
state via `gh`, the git log, and `harness/progress.md`. No new instrumentation is
required of the target repo.

## Why

The engineering-workflow harness imposes discipline (agent pipeline, acceptance
criteria, append-only progress log). That discipline only pays off if you can see
where it's working and where it's being bent. Today every signal lives in raw `gh`
output and a markdown log — there's no surface that says "your tester is the bottleneck"
or "AC was re-edited on 3 of your last 10 issues."

Building this also dogfoods the harness on a real product, exposing harness gaps the
rewrite couldn't anticipate.

## Primary users

- Solo developers and small teams who already use the engineering-workflow harness on
  one or more repos and want to measure their delivery cadence and harness discipline.

## Core user flows

1. **One-shot report for a single repo.** User runs `harness-radar ~/code/foo`. CLI
   queries `gh` for that repo, parses local `harness/progress.md`, prints a markdown
   report to stdout (or writes to `radar-report.md`).
2. **Multi-repo dashboard.** User runs `harness-radar --scan ~/code` against a directory
   of repos. CLI auto-discovers repos with `.claude/harness-mode.json`, aggregates
   metrics, prints a comparative table.
3. **Drill into one issue.** User runs `harness-radar <repo> --issue 42`. Shows the
   issue's full lifecycle: label transitions, project-board status moves, AC edit
   history (the smell signal), time-in-each-pipeline-stage, linked PR cycle time.
4. **AC re-edit audit.** User runs `harness-radar <repo> --ac-audit`. Lists every
   closed issue whose `### Acceptance criteria` block was edited after creation, with
   the diff and the editor's GitHub handle.

## Must-have features (MVP)

- `gh`-based collector that pulls open + closed issues for one repo, including
  body edit history via the GraphQL `userContentEdits` field.
- Lead-time metric: per-issue created → closed, summarized as p50/p90/max for the
  current milestone.
- Throughput metric: issues closed per week, last 8 weeks.
- AC re-edit detector: per-issue boolean + cumulative count, with diff output.
- Agent-pipeline bottleneck signal: time spent in each Projects v2 status (Todo →
  In progress → In review → Done), surfaced as p50/p90 per stage.
- Markdown report output (stdout default; `--out FILE` writes to disk).
- Works on the dogfooded repo (`harness-radar` itself) by day one of v0.1.

## Should-have features

- `--scan` multi-repo aggregation.
- HTML report output (single-file, no JS framework).
- Per-issue drill-down (`--issue N`).
- Local cache of `gh` responses (so repeated runs don't re-hit the API).

## Out of scope (for now)

- Hosted multi-tenant dashboard. This is a local CLI.
- Auth / user management.
- Real-time updates or websockets.
- Integrations with non-GitHub trackers (Jira, Linear).
- Local-mode (`harness/backlog.md`) projects — v0.1 targets github-mode repos only.

## Constraints

- Must read what `gh` and the harness already produce. No new agents, no new files
  in target repos.
- Single binary or single-command install. No databases. SQLite cache is acceptable.
- Stack: leave to the architect, with a steer toward whatever makes `gh` shelling
  and markdown templating cheap (likely Python or Node/TypeScript). Avoid heavy
  frameworks.

## Success criteria

- Runs against `cvsubs74/harness-radar` (this repo) and emits a useful report inside
  the first kickoff session — i.e. the tool is dogfooded before v0.1 ships.
- Detects an AC re-edit when one is deliberately staged in a test fixture.
- Multi-repo `--scan` aggregates ≥ 2 repos correctly.
- Total install + first-run latency under 60 seconds on a clean machine.
