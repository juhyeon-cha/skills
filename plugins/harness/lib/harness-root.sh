#!/usr/bin/env bash
# Legacy transport; native discovery retains the file-presence discriminator.
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/harness-root.mjs" "$@"
