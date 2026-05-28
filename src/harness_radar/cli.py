"""Top-level CLI entrypoint for harness-radar.

Per ADR-0001, the CLI is built on stdlib `argparse` — no third-party CLI
library in v0.1. This module is intentionally thin: it wires up flags,
prints help, and surfaces the version. Subcommand dispatch is a non-goal
for v0.1 (issue #6 Non-goals).

Behavior:
* ``harness-radar --help`` / ``-h``  -> exit 0, prints usage to stdout.
* ``harness-radar`` (no args)        -> exit 0, prints the same usage.
* ``harness-radar --version``        -> exit 0, prints ``harness-radar <semver>``.
* ``harness-radar --unknown-flag``   -> exit 2, error on stderr naming the flag.
"""

from __future__ import annotations

import argparse
import sys
from typing import Sequence

from harness_radar import __version__


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

    # AC #3: no-args invocation prints help and exits 0. argparse's default
    # is to do nothing (since there are no required positionals), so we
    # short-circuit before parse_args.
    if len(argv) == 0:
        parser.print_help(sys.stdout)
        return 0

    # parse_args handles --help / -h (exit 0), --version (exit 0), and
    # unknown flags (exit 2 with stderr message naming the flag).
    parser.parse_args(argv)
    return 0
