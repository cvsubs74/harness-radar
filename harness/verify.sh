#!/usr/bin/env bash
# verify.sh — end-to-end smoke test for this product.
#
# This is a template. The devops agent fills it in during /kickoff
# based on the chosen stack.
#
# Contract:
#   - exit 0 only if everything required for the product to function works
#   - includes a real user-visible check (HTTP probe, CLI invocation, UI assertion)
#   - includes the test suite
#
# Example (Node web app):
#   set -euo pipefail
#   for i in {1..20}; do
#     curl -sf http://localhost:3000 >/dev/null && break
#     sleep 1
#   done
#   curl -sf http://localhost:3000 | grep -q "<title>"
#   npm test
#
# Example (Python API):
#   set -euo pipefail
#   for i in {1..20}; do
#     curl -sf http://localhost:8000/healthz >/dev/null && break
#     sleep 1
#   done
#   curl -sf http://localhost:8000/healthz | jq -e '.status == "ok"'
#   pytest -q
#
# Until /kickoff fills this in, this exits 0 so the harness is usable.

set -euo pipefail

echo "verify.sh: TEMPLATE — fill in via /kickoff (devops agent)."
exit 0
