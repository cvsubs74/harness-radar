"""Shell-out to ``gh`` for issue collection.

Kept as a private module so unit tests can monkey-patch ``subprocess.run``
without reaching into the package's public API. Public re-exports live in
``harness_radar.collector.__init__``.

The collector intentionally uses ``gh issue list --search 'is:issue' ...``
rather than the bare ``gh issue list`` (which would include PRs because
GitHub's REST ``/issues`` endpoint does). A second defensive layer drops
any record that still carries a ``pullRequest`` / ``pull_request`` key —
belt and suspenders for AC3 on issue #10.

Per ADR-0001, the only GitHub I/O path in v0.1 is the ``gh`` CLI. No
direct HTTP, no Octokit, no GraphQL client beyond ``gh api graphql``.
"""

from __future__ import annotations

import json
import re
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

# Issue #10 Non-goals pins the per-call cap at 1000. Repos that exceed
# this threshold are a separate story; the collector does not silently
# paginate past it in v0.1.
_GH_ISSUE_LIMIT = 1000

# Fields to pull. Keep this aligned with ``IssueRecord`` — every field on
# the dataclass must appear here, or ``_record_from_payload`` will crash
# on a ``KeyError`` and surface that the contract drifted.
_GH_JSON_FIELDS = (
    "number,title,body,state,labels,milestone,assignees,author,"
    "createdAt,closedAt"
)

# Parse ``https://github.com/<owner>/<name>(.git)?`` and
# ``git@github.com:<owner>/<name>(.git)?``. The collector only supports
# GitHub remotes in v0.1 (spec: github-only); any other host yields a
# typed CollectorError so the CLI can render a clean message.
_GITHUB_HTTPS_RE = re.compile(
    r"^https?://github\.com/(?P<owner>[^/]+)/(?P<name>[^/]+?)(?:\.git)?/?$"
)
_GITHUB_SSH_RE = re.compile(
    r"^git@github\.com:(?P<owner>[^/]+)/(?P<name>[^/]+?)(?:\.git)?$"
)


class CollectorError(Exception):
    """Raised when the collector cannot fulfil the request.

    Covers: missing/non-GitHub git remote, ``gh`` not on PATH, ``gh``
    exiting non-zero (auth missing, scope missing, repo not found), or a
    malformed JSON payload from ``gh``. The CLI catches this and exits
    1 — same convention as ``RepoValidationError``.
    """


@dataclass(frozen=True)
class IssueRecord:
    """Normalized issue payload — one row per GitHub Issue.

    Frozen so downstream metrics can rely on immutability; sequences are
    ``tuple`` instead of ``list`` for the same reason (and because frozen
    dataclasses are then hashable when their fields are).

    Per AC2 on issue #10, this carries: number, title, body, state,
    labels, milestone title (or None), assignees, author login, created
    timestamp, closed timestamp (or None). Future stories add fields
    (body edits, status events, closing PRs) — they don't rename these.
    """

    number: int
    title: str
    body: str
    state: str  # "OPEN" or "CLOSED" as returned by gh
    labels: tuple[str, ...]
    milestone: str | None
    assignees: tuple[str, ...]
    author: str
    created_at: datetime
    closed_at: datetime | None


def collect_issues(repo_path: Path) -> list[IssueRecord]:
    """Return every issue (open + closed) on the GitHub repo at ``repo_path``.

    Resolves the GitHub slug from ``repo_path``'s ``origin`` remote,
    shells ``gh issue list``, and normalizes the JSON into
    ``IssueRecord``s. PRs are filtered at the source via
    ``--search 'is:issue'`` and again defensively in
    ``_record_from_payload`` (AC3 on issue #10).

    Raises ``CollectorError`` for any failure the user can act on
    (missing/non-GitHub remote, ``gh`` not installed, ``gh`` non-zero
    exit, malformed payload).
    """
    slug = _resolve_github_slug(repo_path)
    payloads = _run_gh_issue_list(slug)
    records: list[IssueRecord] = []
    for payload in payloads:
        # Defensive PR exclusion (AC3). The --search filter should
        # already have done this, but a future ``gh`` regression or a
        # caller bypassing the filter should not silently leak PR rows
        # into the issue list.
        if "pullRequest" in payload or "pull_request" in payload:
            continue
        records.append(_record_from_payload(payload))
    return records


def _resolve_github_slug(repo_path: Path) -> str:
    """Return ``"<owner>/<name>"`` for the GitHub remote at ``repo_path``.

    Reads ``git remote get-url origin``. Raises ``CollectorError`` if
    git itself fails (not a git repo, no origin remote) or if the URL
    isn't a recognisable GitHub URL.
    """
    try:
        result = subprocess.run(
            ["git", "-C", str(repo_path), "remote", "get-url", "origin"],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        # `git` itself not on PATH. Unlikely on a dev machine but a real
        # failure mode in minimal containers — surface it clearly.
        raise CollectorError(
            "git executable not found on PATH; install git to use harness-radar"
        ) from exc
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        raise CollectorError(
            f"{repo_path}: could not read 'origin' remote "
            f"(git exited {exc.returncode}): {stderr}"
        ) from exc

    url = result.stdout.strip()
    for pattern in (_GITHUB_HTTPS_RE, _GITHUB_SSH_RE):
        match = pattern.match(url)
        if match:
            return f"{match.group('owner')}/{match.group('name')}"

    raise CollectorError(
        f"{repo_path}: 'origin' remote is not a GitHub URL ({url!r}); "
        "harness-radar v0.1 supports github-mode repos only"
    )


def _run_gh_issue_list(slug: str) -> list[dict]:
    """Shell ``gh issue list`` for ``slug`` and return parsed JSON.

    Centralised so tests only need to patch one call to mock the gh
    boundary. The command line below is exactly the AC1 baseline (sans
    ``--jq``): same ``--state all --search 'is:issue' --limit 1000``,
    same ``--json`` field set as ``_GH_JSON_FIELDS``.
    """
    cmd = [
        "gh",
        "issue",
        "list",
        "--repo",
        slug,
        "--state",
        "all",
        "--search",
        "is:issue",
        "--limit",
        str(_GH_ISSUE_LIMIT),
        "--json",
        _GH_JSON_FIELDS,
    ]
    try:
        result = subprocess.run(
            cmd,
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise CollectorError(
            "gh CLI not found on PATH; install GitHub CLI "
            "(https://cli.github.com) and run 'gh auth login'"
        ) from exc
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        raise CollectorError(
            f"gh issue list failed for {slug} (exit {exc.returncode}): {stderr}"
        ) from exc

    try:
        payload = json.loads(result.stdout or "[]")
    except json.JSONDecodeError as exc:
        raise CollectorError(
            f"gh issue list returned non-JSON output for {slug}: {exc}"
        ) from exc

    if not isinstance(payload, list):
        raise CollectorError(
            f"gh issue list returned non-list payload for {slug}: "
            f"{type(payload).__name__}"
        )
    return payload


def _record_from_payload(payload: dict) -> IssueRecord:
    """Convert one ``gh`` JSON object into an ``IssueRecord``.

    Tolerates missing optional keys (``milestone`` may be null, ``body``
    may be empty) but raises ``KeyError`` if a required field is
    missing — that signals the ``--json`` field list drifted from
    ``IssueRecord``'s schema and must be fixed in this module, not
    silently papered over.
    """
    milestone = payload.get("milestone")
    milestone_title: str | None
    if isinstance(milestone, dict):
        milestone_title = milestone.get("title")
    else:
        milestone_title = None

    labels = tuple(
        label["name"]
        for label in payload.get("labels", [])
        if isinstance(label, dict) and "name" in label
    )
    assignees = tuple(
        assignee["login"]
        for assignee in payload.get("assignees", [])
        if isinstance(assignee, dict) and "login" in assignee
    )

    author_obj = payload.get("author") or {}
    author_login = author_obj.get("login", "") if isinstance(author_obj, dict) else ""

    return IssueRecord(
        number=int(payload["number"]),
        title=payload.get("title", ""),
        body=payload.get("body", "") or "",
        state=payload["state"],
        labels=labels,
        milestone=milestone_title,
        assignees=assignees,
        author=author_login,
        created_at=_parse_iso8601(payload["createdAt"]),
        closed_at=_parse_iso8601(payload.get("closedAt")),
    )


def _parse_iso8601(value: str | None) -> datetime | None:
    """Parse a GitHub ISO 8601 timestamp (``...Z``) into a ``datetime``.

    Returns ``None`` for ``None`` / empty input so ``closedAt`` on an
    open issue maps cleanly to ``IssueRecord.closed_at = None``. The
    trailing ``Z`` is rewritten to ``+00:00`` because ``fromisoformat``
    in Python 3.11 doesn't accept the ``Z`` shorthand directly.
    """
    if not value:
        return None
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return datetime.fromisoformat(value)
