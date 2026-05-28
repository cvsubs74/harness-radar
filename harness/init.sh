#!/usr/bin/env bash
# init.sh — bring up the development environment for this product.
#
# This is a template. The devops agent fills it in during /kickoff
# based on the chosen stack. Keep it idempotent.
#
# Contract:
#   - exit 0 on success, non-zero on failure
#   - safe to run twice in a row
#   - prints what it's doing
#
# Example (Node web app):
#   command -v node >/dev/null || { echo "install Node 20+"; exit 1; }
#   [ -d node_modules ] || npm ci
#   [ -f .env ] || cp .env.example .env
#   npx prisma migrate dev >/dev/null
#   npm run dev &   # backgrounded; verify.sh waits on it
#
# Example (Python API):
#   command -v python3 >/dev/null || { echo "install Python 3.11+"; exit 1; }
#   [ -d .venv ] || python3 -m venv .venv
#   source .venv/bin/activate
#   pip install -q -r requirements.txt
#   alembic upgrade head
#   uvicorn app.main:app --reload &
#
# Until /kickoff fills this in, no-op succeeds so /verify can run.

set -euo pipefail

echo "init.sh: TEMPLATE — fill in via /kickoff (devops agent)."
exit 0
