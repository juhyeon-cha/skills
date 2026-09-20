#!/usr/bin/env bash
# Offline regression checks; tests/run-all.sh discovers this entry point.
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/document-ac" && pwd)"
python3 "$TEST_DIR/test_checks.py"
