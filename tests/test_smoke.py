"""Smoke test that guarantees the package imports and exposes a version.

This is the seed test the implementer extends as modules land. It keeps
harness/verify.sh honest before any application code is written.
"""

import harness_radar


def test_version_is_non_empty_string() -> None:
    assert isinstance(harness_radar.__version__, str)
    assert harness_radar.__version__ != ""
