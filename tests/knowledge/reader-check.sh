#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/multi_repo" && pwd)"
"${KNOWLEDGE_PYTHON:-python3}" "$TEST_DIR/test_reader.py"
