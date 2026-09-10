#!/bin/bash
set -euo pipefail
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/transcript-contract-check.mjs"
