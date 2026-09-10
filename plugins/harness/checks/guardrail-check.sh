#!/usr/bin/env bash
# Legacy POSIX transport. All policy checks and fixtures live in the Node entry.
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guardrail-check.mjs" "$@"
