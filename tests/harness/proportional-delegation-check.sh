#!/usr/bin/env sh
set -eu
exec node "$(dirname "$0")/proportional-delegation-check.mjs" "$@"
