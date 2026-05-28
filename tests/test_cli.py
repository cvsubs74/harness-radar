"""End-to-end CLI tests for issue #6.

These shell out to the installed ``harness-radar`` console script (via
``pipx``-style entry point) rather than calling ``main()`` in-process, so
the tests exercise the same path a user would.

The five acceptance bullets on #6 map 1:1 to the five test functions below.
"""

from __future__ import annotations

import re
import subprocess

SEMVER_RE = re.compile(r"\b\d+\.\d+\.\d+\b")


def _run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["harness-radar", *args],
        capture_output=True,
        text=True,
    )


def test_help_long_flag_exits_zero_and_prints_usage_and_purpose() -> None:
    res = _run("--help")
    assert res.returncode == 0, res.stderr
    assert "Usage:" in res.stdout
    assert ("velocity" in res.stdout) or ("report" in res.stdout)


def test_help_short_flag_matches_long_flag() -> None:
    long = _run("--help")
    short = _run("-h")
    assert short.returncode == 0, short.stderr
    assert short.stdout == long.stdout


def test_no_args_prints_help_and_exits_zero() -> None:
    no_args = _run()
    help_out = _run("--help")
    assert no_args.returncode == 0, no_args.stderr
    assert "Usage:" in no_args.stdout
    assert no_args.stdout == help_out.stdout


def test_unknown_flag_exits_nonzero_and_names_flag_on_stderr() -> None:
    res = _run("--unknown-flag")
    assert res.returncode != 0
    assert "--unknown-flag" in res.stderr


def test_version_flag_exits_zero_and_prints_semver() -> None:
    res = _run("--version")
    assert res.returncode == 0, res.stderr
    assert SEMVER_RE.search(res.stdout) is not None, res.stdout
