#!/usr/bin/env bash
set -euo pipefail
node "$(cd "$(dirname "$0")" && pwd)/guard-readonly-search-check.mjs"
