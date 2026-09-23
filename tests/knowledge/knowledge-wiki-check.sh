#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -z "${WIKI_MARKDOWN_IT_MODULE:-}" ]]; then
  runtime="$(mktemp -d "${TMPDIR:-/tmp}/knowledge-wiki-runtime.XXXXXX")"
  runtime="$(cd "$runtime" && pwd -P)"
  cp "$ROOT/plugins/knowledge/scripts/wiki/runtime/"*.json "$runtime/"
  npm ci --prefix "$runtime" --ignore-scripts --no-audit --no-fund
  export WIKI_MARKDOWN_IT_MODULE="$runtime/node_modules/markdown-it"
  printf 'External dependency runtime retained: %s\n' "$runtime"
fi
node --test "$ROOT/tests/knowledge/knowledge-wiki-check.mjs"
