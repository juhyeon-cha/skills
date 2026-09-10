#!/usr/bin/env bash
# Legacy POSIX transport; config and Git identity are checked by common Node.
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/workspace-check.mjs" "$@"
