"""Unit tests for ``validate_repo`` — the issue-#7 detection logic.

These run in-process (no subprocess) so the five acceptance cases are
exercised quickly. End-to-end coverage that the CLI actually surfaces
these errors to stderr lives in ``test_cli.py``.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from harness_radar.cli import RepoValidationError, validate_repo


def _make_harness_repo(root: Path, *, mode: str | None = None) -> Path:
    """Build a directory shaped like a github-mode harness repo.

    If ``mode`` is provided, writes ``.claude/harness-mode.json`` with
    that value; otherwise leaves the file absent (which defaults to
    github per CLAUDE.md).
    """
    (root / ".claude").mkdir()
    (root / "harness").mkdir()
    (root / "harness" / "init.sh").write_text("#!/usr/bin/env bash\n")
    if mode is not None:
        (root / ".claude" / "harness-mode.json").write_text(
            json.dumps({"mode": mode})
        )
    return root


# ---- AC1: nonexistent path ----


def test_nonexistent_path_rejected(tmp_path: Path) -> None:
    missing = tmp_path / "does-not-exist-here"
    with pytest.raises(RepoValidationError) as exc:
        validate_repo(missing)
    assert "does not exist" in str(exc.value)


def test_path_is_file_not_directory_rejected(tmp_path: Path) -> None:
    f = tmp_path / "a-file"
    f.write_text("not a directory")
    with pytest.raises(RepoValidationError) as exc:
        validate_repo(f)
    # File-not-a-directory is a degenerate form of "doesn't exist as a
    # repo"; the message stays in the AC1 family so users get one
    # consistent error class for path-shape problems.
    assert "not a directory" in str(exc.value)


# ---- AC2: no .claude/ ----


def test_directory_without_claude_dir_rejected(tmp_path: Path) -> None:
    with pytest.raises(RepoValidationError) as exc:
        validate_repo(tmp_path)
    msg = str(exc.value)
    assert "not a harness repo" in msg
    assert ".claude" in msg


# ---- AC3: .claude/ but no harness/init.sh ----


def test_claude_dir_without_init_sh_rejected(tmp_path: Path) -> None:
    (tmp_path / ".claude").mkdir()
    with pytest.raises(RepoValidationError) as exc:
        validate_repo(tmp_path)
    msg = str(exc.value)
    assert "not a harness repo" in msg
    # Must mention the distinguishing marker so AC3's error is
    # distinguishable from AC2's at-a-glance.
    assert "harness/init.sh" in msg


def test_claude_dir_and_harness_dir_but_no_init_sh_rejected(tmp_path: Path) -> None:
    (tmp_path / ".claude").mkdir()
    (tmp_path / "harness").mkdir()  # dir exists, file does not
    with pytest.raises(RepoValidationError) as exc:
        validate_repo(tmp_path)
    assert "harness/init.sh" in str(exc.value)


# ---- AC4: local mode ----


def test_local_mode_rejected(tmp_path: Path) -> None:
    _make_harness_repo(tmp_path, mode="local")
    with pytest.raises(RepoValidationError) as exc:
        validate_repo(tmp_path)
    assert "local mode is not supported in v0.1" in str(exc.value)


def test_malformed_harness_mode_json_rejected(tmp_path: Path) -> None:
    _make_harness_repo(tmp_path)
    (tmp_path / ".claude" / "harness-mode.json").write_text("{not valid json")
    with pytest.raises(RepoValidationError) as exc:
        validate_repo(tmp_path)
    assert "harness-mode.json" in str(exc.value)


# ---- AC5: valid github-mode repo ----


def test_valid_github_mode_repo_passes_explicit(tmp_path: Path) -> None:
    _make_harness_repo(tmp_path, mode="github")
    # No exception = pass.
    validate_repo(tmp_path)


def test_valid_repo_passes_when_mode_file_absent(tmp_path: Path) -> None:
    # Per CLAUDE.md: absence of harness-mode.json defaults to github.
    _make_harness_repo(tmp_path)
    validate_repo(tmp_path)


def test_unknown_mode_value_passes(tmp_path: Path) -> None:
    # Only "local" is rejected; any other / unexpected value falls
    # through to the github-mode default. This keeps the validator
    # liberal in what it accepts and strict about the one case the
    # collector cannot handle in v0.1.
    _make_harness_repo(tmp_path, mode="github")
    (tmp_path / ".claude" / "harness-mode.json").write_text(
        json.dumps({"mode": "something-else"})
    )
    validate_repo(tmp_path)
