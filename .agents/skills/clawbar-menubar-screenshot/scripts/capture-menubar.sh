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
    if [[ -f "$SEARCH_DIR/Package.swift" && -d "$SEARCH_DIR/Sources" ]]; then
        ROOT_DIR="$SEARCH_DIR"
        break
    fi
    SEARCH_DIR="$(dirname "$SEARCH_DIR")"
done

if [[ -z "$ROOT_DIR" ]]; then
    echo "Unable to locate repository root from $SKILL_DIR" >&2
    exit 1
fi

APP_NAME="${CLAWBAR_CAPTURE_APP_NAME:-Clawbar}"
ITEM_TITLE="${CLAWBAR_CAPTURE_ITEM_TITLE:-Clawbar}"
LAUNCH_WAIT="${CLAWBAR_CAPTURE_LAUNCH_WAIT:-2}"
OPEN_WAIT="${CLAWBAR_CAPTURE_OPEN_WAIT:-1}"
REGION_WIDTH="${CLAWBAR_CAPTURE_REGION_WIDTH:-440}"
REGION_HEIGHT="${CLAWBAR_CAPTURE_REGION_HEIGHT:-600}"
RESTART_APP="${CLAWBAR_CAPTURE_RESTART:-1}"
OUTPUT_ARG="${1:-}"

cd "$ROOT_DIR"

if [[ -z "$OUTPUT_ARG" ]]; then
    OUTPUT_DIR="$ROOT_DIR/Artifacts/MenubarScreenshots"
    mkdir -p "$OUTPUT_DIR"
    OUTPUT_PATH="$OUTPUT_DIR/clawbar-menubar-$(date '+%Y%m%d-%H%M%S').png"
else
    OUTPUT_PATH="$OUTPUT_ARG"
    mkdir -p "$(dirname "$OUTPUT_PATH")"
fi

HARNESS_ARGS=(
    app start
    --mode ui
    --wait-seconds "$LAUNCH_WAIT"
    --openclaw-state installed
    --openclaw-binary-path /opt/homebrew/bin/openclaw
    --openclaw-detail "Provider 已配置 · Gateway 可达 · Channel 已就绪"
    --openclaw-excerpt "OpenClaw 2026.4.2"
)

if [[ "${CLAWBAR_CAPTURE_BUILD:-1}" == "0" ]]; then
    HARNESS_ARGS+=(--no-build)
fi

if [[ "$RESTART_APP" == "1" ]]; then
    HARNESS_ARGS+=(--restart)
fi

STATUS_OUTPUT="$(python3 "$ROOT_DIR/Tests/Harness/clawbarctl.py" app status 2>/dev/null || true)"
if [[ "$RESTART_APP" == "1" || "$STATUS_OUTPUT" != *"state: running"* ]]; then
    python3 "$ROOT_DIR/Tests/Harness/clawbarctl.py" "${HARNESS_ARGS[@]}" >/dev/null
fi

CENTER="$(
swift "$SKILL_DIR/scripts/press_status_item.swift" \
    --app-name "$APP_NAME" \
    --item-title "$ITEM_TITLE"
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
