# Runbook

> Operational notes. Maintained by the devops agent.

## Local development

```bash
bash harness/init.sh    # bring up dev environment (creates .venv/, installs editable + dev extras)
bash harness/verify.sh  # smoke test (ruff + pytest)
```

`init.sh` is idempotent — re-running it is a no-op if `.venv/` already
contains the editable install. To rebuild from scratch, delete `.venv/`
and re-run.

### Prerequisites (init.sh checks these and reports if missing)

| Tool | Min version | Install |
|---|---|---|
| Python | 3.11 | `brew install python@3.11` or pyenv |
| `gh` (GitHub CLI) | 2.49 (sub-issues API) | `brew install gh` |
| `jq` | any recent | `brew install jq` / `apt-get install jq` |

`gh auth status` must succeed. Required scopes: `repo`, `read:org`, `project`.
If a scope is missing: `gh auth refresh -s project,read:org`.

### Activating the venv manually

```bash
source .venv/bin/activate
harness-radar --help    # once the implementer wires cli.main
pytest -q
ruff check src tests
```

## Deploy

Distribution is `pipx install .` from a release tag (or a local checkout). No
hosted infra. End users get a single console entry point (`harness-radar`)
installed in their pipx-managed venv.

```bash
# end-user install (from a clone)
pipx install .

# upgrade
pipx upgrade harness-radar
```

## CI

`.github/workflows/ci.yml` runs on every push and on PRs to `main`. The single
job is named `verify` (branch protection requires that exact name — see
`.claude/commands/kickoff.md`). It uses `actions/setup-python` with pip caching
keyed on `pyproject.toml`, runs `harness/init.sh`, then `harness/verify.sh`.

`gh` is pre-installed on `ubuntu-latest`. We pass `GH_TOKEN: ${{ github.token }}`
so `gh auth status` succeeds inside `init.sh`.

## Common failures

| Symptom | Cause | Fix |
|---|---|---|
| `init.sh: gh is not authenticated` | No `gh auth login` performed (or, in CI, `GH_TOKEN` env not set) | `gh auth login` locally; in CI, confirm the `GH_TOKEN` env block in `ci.yml` |
| `init.sh: gh is too old` | `gh` < 2.49 — sub-issues REST API unavailable | `brew upgrade gh` |
| `init.sh: python3 is too old` | System Python < 3.11 first on PATH | Install Python 3.11+ via pyenv or homebrew and prepend to PATH |
| `verify.sh: FAILED at step: ruff` | Lint error introduced in `src/` or `tests/` | Run `ruff check src tests --fix` locally |
| `verify.sh: FAILED at step: pytest` | A test regressed | Run `pytest -q` and read the failure |
| `pip install -e .[dev]` resolves but `harness-radar` command 404s | `cli.main:main` not yet implemented (expected pre-MVP) | Implementer story will add it; smoke test does not depend on the entry point |

## Secrets

None. The tool delegates all auth to `gh`; no tokens are read or stored.
`.env` is gitignored but currently unused — there is no `.env.example`.

## Observability

CLI logging is stdlib `logging` on stderr, default `WARNING`. `-v` raises to
INFO; `-vv` to DEBUG. There is no remote telemetry.

The on-disk SQLite cache lives under the user cache dir:
- macOS: `~/Library/Caches/harness-radar/`
- Linux: `~/.cache/harness-radar/`

Inspect with `sqlite3 ~/.cache/harness-radar/cache.db '.schema'` once the
cache module lands.
