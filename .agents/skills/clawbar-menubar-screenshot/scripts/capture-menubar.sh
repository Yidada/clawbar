#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.agents/skills/clawbar-menubar-screenshot/scripts/menubar_common.sh
source "$SCRIPT_DIR/menubar_common.sh"

clawbar_menubar_init "${BASH_SOURCE[0]}"

APP_NAME="${CLAWBAR_CAPTURE_APP_NAME:-Clawbar}"
ITEM_TITLE="${CLAWBAR_CAPTURE_ITEM_TITLE:-Clawbar}"
LAUNCH_WAIT="${CLAWBAR_CAPTURE_LAUNCH_WAIT:-2}"
OPEN_WAIT="${CLAWBAR_CAPTURE_OPEN_WAIT:-1}"
REGION_WIDTH="${CLAWBAR_CAPTURE_REGION_WIDTH:-440}"
REGION_HEIGHT="${CLAWBAR_CAPTURE_REGION_HEIGHT:-600}"
RESTART_APP="${CLAWBAR_CAPTURE_RESTART:-1}"
OUTPUT_ARG="${1:-}"

cd "$CLAWBAR_MENUBAR_ROOT_DIR"

if [[ -z "$OUTPUT_ARG" ]]; then
    OUTPUT_DIR="$CLAWBAR_MENUBAR_ROOT_DIR/Artifacts/MenubarScreenshots"
    mkdir -p "$OUTPUT_DIR"
    OUTPUT_PATH="$OUTPUT_DIR/clawbar-menubar-$(date '+%Y%m%d-%H%M%S').png"
else
    OUTPUT_PATH="$OUTPUT_ARG"
    mkdir -p "$(dirname "$OUTPUT_PATH")"
fi

clawbar_menubar_ensure_ui_app_running "$LAUNCH_WAIT" "${CLAWBAR_CAPTURE_BUILD:-1}" "$RESTART_APP" installed

CENTER="$(
clawbar_menubar_press_status_item "$APP_NAME" "$ITEM_TITLE"
)"

sleep "$OPEN_WAIT"
read -r CENTER_X CENTER_Y <<<"$CENTER"
if [[ -z "${CENTER_X:-}" || -z "${CENTER_Y:-}" ]]; then
    echo "Expected click center from press_status_item.swift, got: $CENTER" >&2
    exit 1
fi

REGION_X=$((CENTER_X - REGION_WIDTH / 2))
REGION_Y=0

if (( REGION_X < 0 )); then
    REGION_X=0
fi

screencapture -x -R"${REGION_X},${REGION_Y},${REGION_WIDTH},${REGION_HEIGHT}" "$OUTPUT_PATH"

echo "$OUTPUT_PATH"
