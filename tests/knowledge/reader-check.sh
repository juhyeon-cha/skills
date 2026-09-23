#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/multi_repo" && pwd)"
if [[ -z "${WIKI_MARKDOWN_IT_MODULE:-}" ]]; then
  runtime="$(mktemp -d "${TMPDIR:-/tmp}/knowledge-reader-runtime.XXXXXX")"
  runtime="$(cd "$runtime" && pwd -P)"
  cp "$TEST_DIR/../../../plugins/knowledge/scripts/wiki/runtime/"*.json "$runtime/"
  npm ci --prefix "$runtime" --ignore-scripts --no-audit --no-fund
  export WIKI_MARKDOWN_IT_MODULE="$runtime/node_modules/markdown-it"
  printf 'External dependency runtime retained: %s\n' "$runtime"
fi
"${KNOWLEDGE_PYTHON:-python3}" "$TEST_DIR/test_reader.py"
"${KNOWLEDGE_PYTHON:-python3}" "$TEST_DIR/test_search.py"
