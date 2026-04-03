#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    LINK_TARGET="$(readlink "$SCRIPT_PATH")"
    if [[ "$LINK_TARGET" = /* ]]; then
        SCRIPT_PATH="$LINK_TARGET"
    else
        SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
        SCRIPT_PATH="$(cd "$SCRIPT_DIR" && cd "$(dirname "$LINK_TARGET")" && pwd)/$(basename "$LINK_TARGET")"
    fi
done

SKILL_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
SEARCH_DIR="$SKILL_DIR"
ROOT_DIR=""

while [[ "$SEARCH_DIR" != "/" ]]; do
    if [[ -x "$SEARCH_DIR/Scripts/dev.sh" ]]; then
        ROOT_DIR="$SEARCH_DIR"
        break
    fi
    SEARCH_DIR="$(dirname "$SEARCH_DIR")"
done

if [[ -z "$ROOT_DIR" ]]; then
    echo "Unable to locate repository root from $SKILL_DIR" >&2
    exit 1
fi

DEV_SCRIPT="$ROOT_DIR/Scripts/dev.sh"

if [[ ! -x "$DEV_SCRIPT" ]]; then
    echo "Expected executable dev script at $DEV_SCRIPT" >&2
    exit 1
fi

cd "$ROOT_DIR"
exec "$DEV_SCRIPT"
