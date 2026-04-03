#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$(cd "$SKILL_DIR/../.." && pwd)"
DEV_SCRIPT="$ROOT_DIR/Scripts/dev.sh"

if [[ ! -x "$DEV_SCRIPT" ]]; then
    echo "Expected executable dev script at $DEV_SCRIPT" >&2
    exit 1
fi

cd "$ROOT_DIR"
exec "$DEV_SCRIPT"
