"""Top-level CLI entrypoint for harness-radar.

Per ADR-0001, the CLI is built on stdlib `argparse` — no third-party CLI
library in v0.1. This module is intentionally thin: it wires up flags,
prints help, validates the target repo, and surfaces the version.
Subcommand dispatch is a non-goal for v0.1 (issue #6 Non-goals).

Behavior:
* ``harness-radar --help`` / ``-h``    -> exit 0, prints usage to stdout.
* ``harness-radar`` (no args)          -> exit 0, prints the same usage.
* ``harness-radar --version``          -> exit 0, prints ``harness-radar <semver>``.
* ``harness-radar --unknown-flag``     -> exit 2, error on stderr naming the flag.
* ``harness-radar <repo>``             -> validates the directory is a
  github-mode engineering-workflow harness repo (issue #7), then runs
  the collector (issue #10) to pull every issue (open + closed). On
  validation failure, exits 1 with a distinct error on stderr. On
  collector failure (e.g. ``gh`` missing, non-GitHub remote), exits 1
  with the underlying CollectorError message on stderr. On success,
  prints a one-line summary ``Collected N issues from <owner>/<name>``
  and exits 0. Full report rendering is a future story.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Sequence

from harness_radar import __version__
from harness_radar.collector import CollectorError, collect_issues


class RepoValidationError(Exception):
    """Raised when the target directory is not a valid github-mode harness repo.

    Caught by ``main()`` and rendered to stderr; the message is the only
    user-facing surface. Each call site uses a distinct keyword so the
    five issue-#7 acceptance cases stay individually grep-able by tests.
    """


def validate_repo(path: Path) -> None:
    """Validate that ``path`` is a github-mode engineering-workflow harness repo.

    Raises ``RepoValidationError`` with a clear message on the first
    failed check. Checks run in the order the acceptance criteria list
    them, so the error a user sees matches the most specific failure
    mode.

    Detection signal (per issue #7 Notes): the directory MUST contain
    both ``.claude/`` and ``harness/init.sh``. Mode comes from
    ``.claude/harness-mode.json`` if present; absent file defaults to
    ``github`` per the project's CLAUDE.md contract.
    """
    # AC1: path must exist and be a directory.
    if not path.exists():
        raise RepoValidationError(
            f"{path}: does not exist"
        )
    if not path.is_dir():
        raise RepoValidationError(
            f"{path}: does not exist as a directory (not a directory)"
        )

    # AC2: must have a .claude/ directory.
    claude_dir = path / ".claude"
    if not claude_dir.is_dir():
        raise RepoValidationError(
            f"{path}: not a harness repo (no .claude directory)"
        )

    # AC3: must have harness/init.sh — the second marker that distinguishes
    # an engineering-workflow harness repo from any other repo that happens
    # to have a .claude/ directory.
    init_sh = path / "harness" / "init.sh"
    if not init_sh.is_file():
        raise RepoValidationError(
            f"{path}: not a harness repo (missing harness/init.sh)"
        )

    # AC4: reject local-mode repos. Absent file defaults to github per
    # CLAUDE.md, so we only reject when the file is present AND says local.
    mode_file = claude_dir / "harness-mode.json"
    if mode_file.is_file():
        try:
            mode_payload = json.loads(mode_file.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            raise RepoValidationError(
                f"{mode_file}: could not parse harness-mode.json: {exc}"
            ) from exc
        mode = mode_payload.get("mode") if isinstance(mode_payload, dict) else None
        if mode == "local":
            raise RepoValidationError(
                f"{path}: local mode is not supported in v0.1 "
                "(only github-mode harness repos are supported)"
            )


class _CapitalUsageFormatter(argparse.HelpFormatter):
    """Help formatter that emits ``Usage:`` (capital U).

    argparse defaults to lowercase ``usage:``. AC #1 on issue #6 requires
    stdout to contain ``Usage:`` (capital U), so we override the prefix.
    """

    def add_usage(  # type: ignore[override]
        self,
        usage: str | None,
        actions,
        groups,
        prefix: str | None = None,
    ) -> None:
        if prefix is None:
            prefix = "Usage: "
        super().add_usage(usage, actions, groups, prefix)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="harness-radar",
        description=(
            "Emit velocity and harness-discipline reports for repos using "
            "the engineering-workflow harness."
        ),
        formatter_class=_CapitalUsageFormatter,
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"harness-radar {__version__}",
    )
    # nargs="?" + default="." keeps the issue-#6 no-args -> help behavior
    # intact: when argv is empty we short-circuit to print_help before
    # argparse ever runs, so the default is only consumed when other
    # arguments are supplied without a positional.
    parser.add_argument(
        "repo",
        nargs="?",
        default=".",
        help=(
            "Path to a github-mode engineering-workflow harness repo "
            "(default: current directory)."
        ),
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """Run the harness-radar CLI.

    Returns the process exit code so the console-script wrapper can pass
    it to ``sys.exit``. Argparse itself raises ``SystemExit`` for help,
    version, and usage errors — we let those propagate.
    """
    if argv is None:
        argv = sys.argv[1:]

    parser = _build_parser()

    # AC #3 on issue #6: no-args invocation prints help and exits 0.
    # Short-circuit before argparse so the positional default isn't
    # silently exercised against the cwd.
    if len(argv) == 0:
        parser.print_help(sys.stdout)
        return 0

    # parse_args handles --help / -h (exit 0), --version (exit 0), and
    # unknown flags (exit 2 with stderr message naming the flag).
    args = parser.parse_args(argv)

    # Issue #7: validate the target repo before any downstream work.
    repo_path = Path(args.repo)
    try:
        validate_repo(repo_path)
    except RepoValidationError as exc:
        print(f"harness-radar: {exc}", file=sys.stderr)
        return 1

    # Issue #10: pull every issue (open + closed) from the target repo.
    # Full report rendering is a future story; this story is about
    # proving the data path. The summary line keeps the test surface
    # mechanical (count + slug) without committing to any report shape.
    try:
        records = collect_issues(repo_path)
    except CollectorError as exc:
        print(f"harness-radar: {exc}", file=sys.stderr)
        return 1

    slug = _format_slug(repo_path)
    print(f"Collected {len(records)} issues from {slug}")
    return 0


def _format_slug(repo_path: Path) -> str:
    """Best-effort ``<owner>/<name>`` for the post-collect summary line.

    On any failure (no git, no origin, non-GitHub URL) we fall back to
    the bare path string. The collector already validated the remote
    when it ran successfully, so this is purely a presentation helper
    and must not raise — a partial summary is still better than a
    crash after we've already pulled the data.
    """
    from harness_radar.collector.gh import _resolve_github_slug

    try:
        return _resolve_github_slug(repo_path)
    except CollectorError:
        return str(repo_path)
