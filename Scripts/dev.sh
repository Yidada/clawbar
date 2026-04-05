#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$ROOT_DIR/Tests/Harness/clawbarctl.py" app dev-loop --poll-interval "${CLAWBAR_DEV_POLL_INTERVAL:-1}"
