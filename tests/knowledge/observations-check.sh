#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "${KNOWLEDGE_PYTHON:-python3}" -B "$ROOT/tests/knowledge/observations-check.py"
