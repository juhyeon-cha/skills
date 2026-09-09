#!/usr/bin/env bash
# Legacy POSIX transport; shared native implementation is the adjacent Node entrypoint.
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/board-check.mjs" "$@"
