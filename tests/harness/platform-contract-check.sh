#!/usr/bin/env bash
# POSIX convenience only; CI runs the same .mjs directly on every native host.
set -eu
exec node "$(cd "$(dirname "$0")" && pwd)/platform-contract-check.mjs" "$@"
