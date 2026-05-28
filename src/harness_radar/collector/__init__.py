"""Collector package — pulls GitHub data via ``gh`` into typed dataclasses.

This is the spine of harness-radar. Issue #10 shipped the first slice:
every issue (open + closed) on a target repo as a list of
``IssueRecord`` objects. Issue #11 adds lazy edit-history collection:
``collect_edits(repo_slug, issue_number)`` returns an
``EditRecord`` tuple per issue, fetched on demand so ``collect_issues``
doesn't pay an N+1 GraphQL cost. Future stories in ``area:collector``
enrich the model (project status events, closing PR linkage) without
changing this public surface — they add fields, they don't replace the
existing calls.

Per ADR-0001, records are plain ``dataclass``es; no pydantic / attrs /
TypedDict. Frozen + tuple-typed sequences so downstream ``metrics``
functions can rely on immutability without defensive copying.
"""

from __future__ import annotations

from .gh import (
    CollectorError,
    EditRecord,
    IssueRecord,
    collect_edits,
    collect_issues,
)

__all__ = [
    "CollectorError",
    "EditRecord",
    "IssueRecord",
    "collect_edits",
    "collect_issues",
]
