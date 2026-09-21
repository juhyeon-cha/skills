#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/automation" && pwd)"
"${KNOWLEDGE_PYTHON:-python3}" "$TEST_DIR/test_automation.py"
