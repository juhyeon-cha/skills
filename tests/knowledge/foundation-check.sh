#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${KNOWLEDGE_PYTHON:-python3}" "$HERE/foundation-evaluation/check.py"
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
"${KNOWLEDGE_PYTHON:-python3}" "$HERE/foundation-observation/replay.py" --out "$output/result"
