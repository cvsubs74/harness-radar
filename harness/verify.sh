#!/usr/bin/env bash
# verify.sh — end-to-end smoke test for harness-radar.
#
# Runs lint + tests inside the project venv. Re-bootstraps the venv via
# init.sh if missing, so a fresh clone can `bash harness/verify.sh` directly.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${REPO_ROOT}/.venv"

if [ ! -x "${VENV_DIR}/bin/python" ]; then
  echo "verify.sh: .venv missing — running init.sh"
  bash "${REPO_ROOT}/harness/init.sh"
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

step() {
  echo "verify.sh: -> $*"
}

fail() {
  echo "verify.sh: FAILED at step: $*" >&2
  exit 1
}

step "ruff check"
ruff check "${REPO_ROOT}/src" "${REPO_ROOT}/tests" || fail "ruff"

step "pytest"
pytest -q "${REPO_ROOT}/tests" || fail "pytest"

echo "verify.sh: verify OK"
