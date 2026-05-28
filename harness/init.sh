#!/usr/bin/env bash
# init.sh — bring up the development environment for harness-radar.
#
# Stack: Python 3.11+ package, stdlib sqlite3 + subprocess, jinja2, pytest, ruff.
# Runtime hard dep on the `gh` CLI (sub-issues API requires >= 2.49) and `jq`.
#
# Idempotent: re-running is a no-op if everything is already in place.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${REPO_ROOT}/.venv"

# ---- prerequisite checks (we do NOT install these for the user) ----

require_cmd() {
  local cmd="$1"
  local hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "init.sh: missing required tool: ${cmd}" >&2
    echo "init.sh: fix: ${hint}" >&2
    exit 1
  fi
}

require_cmd python3 "install Python >= 3.11 (e.g. 'brew install python@3.11' or use pyenv)"
require_cmd gh "install GitHub CLI >= 2.49 (e.g. 'brew install gh')"
require_cmd jq "install jq (e.g. 'brew install jq' or 'apt-get install jq')"

# Python >= 3.11
PY_OK="$(python3 -c 'import sys; print(1 if sys.version_info >= (3, 11) else 0)')"
if [ "${PY_OK}" != "1" ]; then
  echo "init.sh: python3 is too old: $(python3 --version)" >&2
  echo "init.sh: fix: install Python >= 3.11 and ensure it is first on PATH" >&2
  exit 1
fi

# gh >= 2.49 (sub-issues API)
GH_VER="$(gh --version | awk 'NR==1 {print $3}')"
GH_OK="$(python3 -c "
import sys
v = '${GH_VER}'.split('.')
try:
    major, minor = int(v[0]), int(v[1])
except (ValueError, IndexError):
    sys.exit(0)
print(1 if (major, minor) >= (2, 49) else 0)
")"
if [ "${GH_OK}" != "1" ]; then
  echo "init.sh: gh is too old: ${GH_VER} (need >= 2.49 for sub-issues API)" >&2
  echo "init.sh: fix: upgrade gh (e.g. 'brew upgrade gh')" >&2
  exit 1
fi

# gh auth
if ! gh auth status >/dev/null 2>&1; then
  echo "init.sh: gh is not authenticated" >&2
  echo "init.sh: fix: run 'gh auth login' (scopes needed: repo, read:org, project)" >&2
  exit 1
fi

# ---- virtualenv (idempotent) ----

if [ ! -d "${VENV_DIR}" ]; then
  echo "init.sh: creating virtualenv at ${VENV_DIR}"
  python3 -m venv "${VENV_DIR}"
else
  echo "init.sh: reusing existing virtualenv at ${VENV_DIR}"
fi

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

# Keep pip current quietly. Idempotent — pip skips if already satisfied.
python -m pip install --quiet --upgrade pip

# ---- project install (editable + dev extras) ----

echo "init.sh: installing harness-radar (editable, dev extras)"
pip install --quiet -e "${REPO_ROOT}[dev]"

echo "init.sh: init OK"
