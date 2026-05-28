"""Tests for ``harness_radar.collector`` — issue #10.

Unit tests mock ``subprocess.run`` so the gh boundary stays at one
function (``_run_gh_issue_list``). One end-to-end test runs the
collector against this repo's real GitHub remote and exercises AC4
(count parity + presence of #1).

The five AC bullets on issue #10 map to:
* AC1 — count parity vs `gh issue list --jq 'length'`. The e2e test
  computes the same integer two ways and asserts equality.
* AC2 — each ``IssueRecord`` has the canonicalised field set.
  ``test_record_has_all_canonicalised_fields`` checks every field.
* AC3 — source-level filter (the gh command line uses
  ``--search 'is:issue'``) AND a defensive runtime filter dropping
  rows that still carry ``pullRequest`` / ``pull_request``. Both
  layers have dedicated tests.
* AC4 — dogfooded against ``cvsubs74/harness-radar`` with #1 present.
"""

from __future__ import annotations

import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

import pytest

from harness_radar.collector import CollectorError, IssueRecord, collect_issues
from harness_radar.collector.gh import (
    _GH_ISSUE_LIMIT,
    _record_from_payload,
    _resolve_github_slug,
    _run_gh_issue_list,
)

REPO_ROOT = Path(__file__).resolve().parent.parent

# ---- Fixtures: synthetic gh payloads ----


def _fake_issue(number: int, *, state: str = "OPEN", closed_at: str | None = None) -> dict:
    """Build one synthetic gh-shaped issue payload.

    Field set mirrors what ``gh issue list --json
    number,title,body,state,labels,milestone,assignees,author,createdAt,closedAt``
    actually returns. Keeping the shape true to the wire format means
    these unit tests fail loudly if the dataclass schema drifts.
    """
    return {
        "number": number,
        "title": f"[Story] fake issue {number}",
        "body": f"body for #{number}",
        "state": state,
        "labels": [
            {"name": "type:story", "color": "1d76db", "description": ""},
            {"name": "priority:P1", "color": "d93f0b", "description": ""},
        ],
        "milestone": None,
        "assignees": [{"login": "alice"}],
        "author": {"login": "bob", "is_bot": False, "name": ""},
        "createdAt": "2026-05-20T12:00:00Z",
        "closedAt": closed_at,
    }


def _fake_pr_leaking_through(number: int) -> dict:
    """A PR-shaped payload with the ``pullRequest`` key set.

    Used to exercise the defensive AC3 filter. If `--search 'is:issue'`
    is bypassed or regresses, the collector still drops these rows.
    """
    payload = _fake_issue(number, state="OPEN")
    payload["pullRequest"] = {"url": f"https://example/pulls/{number}"}
    return payload


def _patch_gh_returning(payloads: list[dict]):
    """Patch ``subprocess.run`` so any ``gh`` call returns ``payloads`` as JSON.

    ``git remote get-url origin`` is still allowed to run for real,
    because the collector calls it first. We only intercept the ``gh``
    subcommand. Tests that need to mock the git call too should patch
    ``_resolve_github_slug`` directly.
    """
    real_run = subprocess.run

    def fake_run(cmd, *args, **kwargs):
        if isinstance(cmd, (list, tuple)) and cmd and cmd[0] == "gh":
            return subprocess.CompletedProcess(
                args=cmd,
                returncode=0,
                stdout=json.dumps(payloads),
                stderr="",
            )
        return real_run(cmd, *args, **kwargs)

    return patch("harness_radar.collector.gh.subprocess.run", side_effect=fake_run)


# ---- Unit tests: dataclass + payload mapping ----


def test_record_has_all_canonicalised_fields() -> None:
    """AC2: every field on the canonical schema is on the dataclass."""
    payload = _fake_issue(7, state="CLOSED", closed_at="2026-05-25T09:30:00Z")
    payload["milestone"] = {"title": "v0.1", "number": 1}
    record = _record_from_payload(payload)

    assert record.number == 7
    assert record.title == "[Story] fake issue 7"
    assert record.body == "body for #7"
    assert record.state == "CLOSED"
    assert record.labels == ("type:story", "priority:P1")
    assert record.milestone == "v0.1"
    assert record.assignees == ("alice",)
    assert record.author == "bob"
    assert record.created_at == datetime(2026, 5, 20, 12, 0, 0, tzinfo=timezone.utc)
    assert record.closed_at == datetime(2026, 5, 25, 9, 30, 0, tzinfo=timezone.utc)


def test_record_handles_open_issue_with_null_closed_at_and_no_milestone() -> None:
    """Open issues have ``closedAt=null`` and frequently no milestone."""
    payload = _fake_issue(8, state="OPEN", closed_at=None)
    record = _record_from_payload(payload)
    assert record.closed_at is None
    assert record.milestone is None


def test_record_is_frozen() -> None:
    """Frozen dataclass — downstream metrics must not mutate."""
    record = _record_from_payload(_fake_issue(1))
    with pytest.raises(Exception):  # FrozenInstanceError on 3.11+
        record.title = "mutated"  # type: ignore[misc]


def test_record_uses_tuple_sequences_not_list() -> None:
    """``tuple`` not ``list`` so the frozen dataclass stays hashable."""
    record = _record_from_payload(_fake_issue(1))
    assert isinstance(record.labels, tuple)
    assert isinstance(record.assignees, tuple)


# ---- Unit tests: collect_issues happy path + filtering ----


def test_collect_returns_three_records_when_gh_returns_three_issues() -> None:
    payloads = [_fake_issue(1), _fake_issue(2, state="CLOSED",
                                            closed_at="2026-05-25T09:30:00Z"),
                _fake_issue(3)]
    with patch(
        "harness_radar.collector.gh._resolve_github_slug",
        return_value="cvsubs74/harness-radar",
    ), _patch_gh_returning(payloads):
        records = collect_issues(REPO_ROOT)
    assert len(records) == 3
    assert {r.number for r in records} == {1, 2, 3}
    assert all(isinstance(r, IssueRecord) for r in records)


def test_collect_returns_empty_list_for_empty_repo() -> None:
    with patch(
        "harness_radar.collector.gh._resolve_github_slug",
        return_value="cvsubs74/harness-radar",
    ), _patch_gh_returning([]):
        records = collect_issues(REPO_ROOT)
    assert records == []


def test_collect_drops_three_issues_plus_two_pr_leakers() -> None:
    """AC3 defensive layer: PRs that slip through ``--search`` are dropped."""
    payloads = [
        _fake_issue(10),
        _fake_pr_leaking_through(11),
        _fake_issue(12),
        _fake_pr_leaking_through(13),
        _fake_issue(14),
    ]
    with patch(
        "harness_radar.collector.gh._resolve_github_slug",
        return_value="cvsubs74/harness-radar",
    ), _patch_gh_returning(payloads):
        records = collect_issues(REPO_ROOT)
    assert {r.number for r in records} == {10, 12, 14}


def test_collect_drops_snake_case_pull_request_key_too() -> None:
    """REST shape uses ``pull_request`` (snake); GraphQL uses ``pullRequest``.

    Belt-and-suspenders for AC3 — we filter both casings so a future
    swap of the source endpoint doesn't silently leak PRs.
    """
    payload = _fake_issue(20)
    payload["pull_request"] = {"url": "https://example/pulls/20"}
    with patch(
        "harness_radar.collector.gh._resolve_github_slug",
        return_value="cvsubs74/harness-radar",
    ), _patch_gh_returning([_fake_issue(21), payload]):
        records = collect_issues(REPO_ROOT)
    assert {r.number for r in records} == {21}


# ---- Unit tests: error surfaces ----


def test_gh_not_on_path_raises_collector_error() -> None:
    def fake_run(cmd, *args, **kwargs):
        if isinstance(cmd, (list, tuple)) and cmd and cmd[0] == "gh":
            raise FileNotFoundError("gh")
        return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="", stderr="")

    with patch(
        "harness_radar.collector.gh._resolve_github_slug",
        return_value="cvsubs74/harness-radar",
    ), patch("harness_radar.collector.gh.subprocess.run", side_effect=fake_run):
        with pytest.raises(CollectorError) as exc:
            collect_issues(REPO_ROOT)
    assert "gh CLI not found" in str(exc.value)


def test_gh_nonzero_exit_raises_collector_error() -> None:
    def fake_run(cmd, *args, **kwargs):
        if isinstance(cmd, (list, tuple)) and cmd and cmd[0] == "gh":
            raise subprocess.CalledProcessError(
                returncode=4,
                cmd=cmd,
                stderr="HTTP 404: Not Found",
            )
        return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="", stderr="")

    with patch(
        "harness_radar.collector.gh._resolve_github_slug",
        return_value="cvsubs74/harness-radar",
    ), patch("harness_radar.collector.gh.subprocess.run", side_effect=fake_run):
        with pytest.raises(CollectorError) as exc:
            collect_issues(REPO_ROOT)
    msg = str(exc.value)
    assert "gh issue list failed" in msg
    assert "exit 4" in msg
    assert "Not Found" in msg


def test_gh_returning_non_json_raises_collector_error() -> None:
    def fake_run(cmd, *args, **kwargs):
        if isinstance(cmd, (list, tuple)) and cmd and cmd[0] == "gh":
            return subprocess.CompletedProcess(
                args=cmd, returncode=0, stdout="not json at all", stderr=""
            )
        return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="", stderr="")

    with patch(
        "harness_radar.collector.gh._resolve_github_slug",
        return_value="cvsubs74/harness-radar",
    ), patch("harness_radar.collector.gh.subprocess.run", side_effect=fake_run):
        with pytest.raises(CollectorError) as exc:
            collect_issues(REPO_ROOT)
    assert "non-JSON" in str(exc.value)


# ---- Unit tests: slug resolution ----


def test_resolve_slug_from_https_remote(tmp_path: Path) -> None:
    def fake_run(cmd, *args, **kwargs):
        if isinstance(cmd, (list, tuple)) and "remote" in cmd:
            return subprocess.CompletedProcess(
                args=cmd,
                returncode=0,
                stdout="https://github.com/cvsubs74/harness-radar.git\n",
                stderr="",
            )
        raise AssertionError(f"unexpected cmd: {cmd}")

    with patch("harness_radar.collector.gh.subprocess.run", side_effect=fake_run):
        assert _resolve_github_slug(tmp_path) == "cvsubs74/harness-radar"


def test_resolve_slug_from_ssh_remote(tmp_path: Path) -> None:
    def fake_run(cmd, *args, **kwargs):
        return subprocess.CompletedProcess(
            args=cmd,
            returncode=0,
            stdout="git@github.com:cvsubs74/harness-radar.git\n",
            stderr="",
        )

    with patch("harness_radar.collector.gh.subprocess.run", side_effect=fake_run):
        assert _resolve_github_slug(tmp_path) == "cvsubs74/harness-radar"


def test_resolve_slug_rejects_non_github_remote(tmp_path: Path) -> None:
    def fake_run(cmd, *args, **kwargs):
        return subprocess.CompletedProcess(
            args=cmd,
            returncode=0,
            stdout="https://gitlab.com/example/repo.git\n",
            stderr="",
        )

    with patch("harness_radar.collector.gh.subprocess.run", side_effect=fake_run):
        with pytest.raises(CollectorError) as exc:
            _resolve_github_slug(tmp_path)
    assert "not a GitHub URL" in str(exc.value)


def test_resolve_slug_surfaces_git_failure(tmp_path: Path) -> None:
    def fake_run(cmd, *args, **kwargs):
        raise subprocess.CalledProcessError(
            returncode=128,
            cmd=cmd,
            stderr="fatal: No such remote 'origin'",
        )

    with patch("harness_radar.collector.gh.subprocess.run", side_effect=fake_run):
        with pytest.raises(CollectorError) as exc:
            _resolve_github_slug(tmp_path)
    assert "could not read 'origin' remote" in str(exc.value)


# ---- Unit tests: gh command line is the AC1 baseline ----


def test_gh_command_line_matches_ac1_baseline() -> None:
    """AC1 + AC3: the gh invocation uses ``--state all --search 'is:issue'
    --limit 1000`` so its count matches the AC1 ``--jq 'length'`` baseline.
    """
    captured: dict = {}

    def fake_run(cmd, *args, **kwargs):
        captured["cmd"] = cmd
        return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="[]", stderr="")

    with patch("harness_radar.collector.gh.subprocess.run", side_effect=fake_run):
        _run_gh_issue_list("cvsubs74/harness-radar")

    cmd = captured["cmd"]
    assert cmd[0] == "gh"
    assert "--state" in cmd and cmd[cmd.index("--state") + 1] == "all"
    assert "--search" in cmd and cmd[cmd.index("--search") + 1] == "is:issue"
    assert "--limit" in cmd and cmd[cmd.index("--limit") + 1] == str(_GH_ISSUE_LIMIT)
    assert "--repo" in cmd and cmd[cmd.index("--repo") + 1] == "cvsubs74/harness-radar"
    # All canonical fields must be requested.
    json_arg = cmd[cmd.index("--json") + 1]
    for field in (
        "number", "title", "body", "state", "labels",
        "milestone", "assignees", "author", "createdAt", "closedAt",
    ):
        assert field in json_arg, f"missing --json field: {field}"


# ---- End-to-end: AC4 dogfood against cvsubs74/harness-radar ----


def _gh_baseline_count() -> int:
    """Compute the AC1 baseline integer via the exact command in the AC."""
    result = subprocess.run(
        [
            "gh", "issue", "list", "--repo", "cvsubs74/harness-radar",
            "--state", "all", "--search", "is:issue",
            "--limit", "1000", "--json", "number", "--jq", "length",
        ],
        check=True, capture_output=True, text=True,
    )
    return int(result.stdout.strip())


def test_collect_against_this_repo_matches_baseline_and_includes_issue_1() -> None:
    """AC4: against ``cvsubs74/harness-radar``,
    * count of returned records equals the AC1 baseline integer
    * issue #1 (parent epic for collector work) is present.

    This is the load-bearing dogfood test. It requires the dev machine
    to be ``gh auth``'ed to GitHub. If gh is missing we skip rather
    than fail — the unit tests above already cover the missing-gh
    error path with a mock.
    """
    try:
        baseline = _gh_baseline_count()
    except (FileNotFoundError, subprocess.CalledProcessError):
        pytest.skip("gh CLI not available or not authenticated")

    records = collect_issues(REPO_ROOT)
    assert len(records) == baseline, (
        f"collector returned {len(records)} but gh --jq length returned {baseline}"
    )
    numbers = {r.number for r in records}
    assert 1 in numbers, "issue #1 (parent epic for collector work) is missing"
    # Sanity floor: this repo has ~30 issues from kickoff seeding.
    assert len(records) >= 30
