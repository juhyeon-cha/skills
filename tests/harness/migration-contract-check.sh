#!/usr/bin/env bash
# POSIX migration integration: actual Bash preparation/ledger transport in temp copies.
set -eu
exec node "$(cd "$(dirname "$0")" && pwd)/migration-contract-check.mjs" "$@"
