#!/usr/bin/env bash
set -euo pipefail
node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state-contract-check.mjs"
