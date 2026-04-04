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

if [[ "${CLAWBAR_VERIFY_BUILD:-1}" != "0" ]]; then
    swift build >/dev/null
fi

APP_BINARY_REAL="$(
    python3 - <<'PY'
from pathlib import Path
print(Path(".build/debug/Clawbar").resolve())
PY
)"

if [[ ! -x "$APP_BINARY_REAL" ]]; then
    echo "Expected built Clawbar binary at $APP_BINARY_REAL" >&2
    exit 1
fi

if [[ "${CLAWBAR_VERIFY_RESTART:-1}" == "1" ]]; then
    pkill -f "$APP_BINARY_REAL" >/dev/null 2>&1 || true
    sleep 1
fi

if ! pgrep -f "$APP_BINARY_REAL" >/dev/null 2>&1; then
    if [[ "$VERIFY_STATE" == "installed" ]]; then
        LAUNCH_COMMAND="cd \"$ROOT_DIR\" && env CLAWBAR_UI_TEST=1 CLAWBAR_TEST_OPENCLAW_STATE=installed CLAWBAR_TEST_OPENCLAW_BINARY_PATH=/opt/homebrew/bin/openclaw CLAWBAR_TEST_OPENCLAW_DETAIL='status 已返回最近状态。' CLAWBAR_TEST_OPENCLAW_EXCERPT='plugins.allow is empty; discovered non-bundled plugins.' \"$APP_BINARY_REAL\""
    else
        LAUNCH_COMMAND="cd \"$ROOT_DIR\" && env CLAWBAR_UI_TEST=1 CLAWBAR_TEST_OPENCLAW_STATE=missing \"$APP_BINARY_REAL\""
    fi

    osascript - "$LAUNCH_COMMAND" <<'APPLESCRIPT' >/dev/null
on run argv
    tell application "Terminal"
        activate
        do script (item 1 of argv)
    end tell
end run
APPLESCRIPT
    sleep "$LAUNCH_WAIT"
fi

swift "$SKILL_DIR/scripts/press_status_item.swift" \
    --app-name "$APP_NAME" \
    --item-title "$ITEM_TITLE" >/dev/null

sleep "$OPEN_WAIT"

VERIFY_ARGS=(
    --app-name "$APP_NAME"
    --item-title "$ITEM_TITLE"
    --expect "Hello World"
    --expect "This is the smallest possible Clawbar scaffold."
    --expect "Settings"
    --expect "Quit"
)

if [[ "$VERIFY_STATE" == "installed" ]]; then
    VERIFY_ARGS+=(
        --expect "OpenClaw"
        --expect "/opt/homebrew/bin/openclaw"
        --expect "status 已返回最近状态。"
        --expect "plugins.allow is empty; discovered non-bundled plugins."
        --expect "启动 TUI 调试终端"
        --expect "卸载 OpenClaw"
    )
else
    VERIFY_ARGS+=(
        --expect "安装 OpenClaw"
    )
fi

swift "$SKILL_DIR/scripts/verify_menu.swift" "${VERIFY_ARGS[@]}"
