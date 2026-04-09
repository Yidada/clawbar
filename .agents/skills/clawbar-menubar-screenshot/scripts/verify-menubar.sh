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

APP_NAME="${CLAWBAR_VERIFY_APP_NAME:-Clawbar}"
ITEM_TITLE="${CLAWBAR_VERIFY_ITEM_TITLE:-Clawbar}"
LAUNCH_WAIT="${CLAWBAR_VERIFY_LAUNCH_WAIT:-2}"
OPEN_WAIT="${CLAWBAR_VERIFY_OPEN_WAIT:-1}"
VERIFY_STATE="${CLAWBAR_VERIFY_OPENCLAW_STATE:-installed}"

cd "$ROOT_DIR"

HARNESS_ARGS=(
    app start
    --mode ui
    --wait-seconds "$LAUNCH_WAIT"
    --openclaw-state "$VERIFY_STATE"
)

if [[ "$VERIFY_STATE" == "installed" ]]; then
    HARNESS_ARGS+=(
        --openclaw-binary-path /opt/homebrew/bin/openclaw
        --openclaw-detail "Provider 已配置 · Gateway 可达 · Channel 已就绪"
        --openclaw-excerpt "OpenClaw 2026.4.2"
    )
fi

if [[ "${CLAWBAR_VERIFY_BUILD:-1}" == "0" ]]; then
    HARNESS_ARGS+=(--no-build)
fi

if [[ "${CLAWBAR_VERIFY_RESTART:-1}" == "1" ]]; then
    HARNESS_ARGS+=(--restart)
fi

STATUS_OUTPUT="$(python3 "$ROOT_DIR/Tests/Harness/clawbarctl.py" app status 2>/dev/null || true)"
if [[ "${CLAWBAR_VERIFY_RESTART:-1}" == "1" || "$STATUS_OUTPUT" != *"state: running"* ]]; then
    python3 "$ROOT_DIR/Tests/Harness/clawbarctl.py" "${HARNESS_ARGS[@]}" >/dev/null
fi

swift "$SKILL_DIR/scripts/press_status_item.swift" \
    --app-name "$APP_NAME" \
    --item-title "$ITEM_TITLE" >/dev/null

sleep "$OPEN_WAIT"

VERIFY_ARGS=(
    --app-name "$APP_NAME"
    --expect "OpenClaw"
    --expect "Settings"
    --expect "Quit"
    --expect "Provider"
    --expect "Gateway"
    --expect "Channel"
)

if [[ "$VERIFY_STATE" == "installed" ]]; then
    VERIFY_ARGS+=(
        --expect "/opt/homebrew/bin/openclaw"
        --expect "OpenClaw 2026.4.2"
        --expect "启动 TUI"
        --expect "卸载 OpenClaw"
    )
else
    VERIFY_ARGS+=(
        --expect "OpenClaw 未安装"
        --expect "安装 OpenClaw"
    )
fi

swift "$SKILL_DIR/scripts/verify_popup.swift" "${VERIFY_ARGS[@]}"
