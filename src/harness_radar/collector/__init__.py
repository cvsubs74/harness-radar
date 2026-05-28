"""Collector package — pulls GitHub data via ``gh`` into typed dataclasses.

This is the spine of harness-radar. Issue #10 ships the first slice: every
issue (open + closed) on a target repo as a list of ``IssueRecord`` objects.
Future stories in ``area:collector`` enrich the model (body edit history,
project status events, closing PR linkage) without changing this public
surface — they add fields, they don't replace the call.

Per ADR-0001, records are plain ``dataclass``es; no pydantic / attrs /
TypedDict. Frozen + tuple-typed sequences so downstream ``metrics``
functions can rely on immutability without defensive copying.
"""

from __future__ import annotations

from .gh import (
    CollectorError,
    IssueRecord,
    collect_issues,
)

__all__ = [
    "CollectorError",
    "IssueRecord",
    "collect_issues",
]
