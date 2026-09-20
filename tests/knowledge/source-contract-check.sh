#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/source-contract" && pwd)"
"${KNOWLEDGE_PYTHON:-python3}" "$TEST_DIR/test_cli.py"
"${KNOWLEDGE_PYTHON:-python3}" "$TEST_DIR/test_impact.py"
"${KNOWLEDGE_PYTHON:-python3}" "$TEST_DIR/test_update.py"
"${KNOWLEDGE_PYTHON:-python3}" "$TEST_DIR/test_workflow.py"
"${KNOWLEDGE_PYTHON:-python3}" "$TEST_DIR/test_project.py"
"${KNOWLEDGE_PYTHON:-python3}" "$TEST_DIR/test_intake.py"
"${KNOWLEDGE_PYTHON:-python3}" "$TEST_DIR/test_public_contract.py"
"${KNOWLEDGE_PYTHON:-python3}" "$TEST_DIR/test_legacy_compatibility.py"
