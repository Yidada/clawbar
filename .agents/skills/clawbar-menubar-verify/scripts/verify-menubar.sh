#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.agents/skills/clawbar-menubar-screenshot/scripts/menubar_common.sh
source "$SCRIPT_DIR/../../clawbar-menubar-screenshot/scripts/menubar_common.sh"

clawbar_menubar_init "${BASH_SOURCE[0]}"

APP_NAME="${CLAWBAR_VERIFY_APP_NAME:-Clawbar}"
ITEM_TITLE="${CLAWBAR_VERIFY_ITEM_TITLE:-Clawbar}"
LAUNCH_WAIT="${CLAWBAR_VERIFY_LAUNCH_WAIT:-2}"
OPEN_WAIT="${CLAWBAR_VERIFY_OPEN_WAIT:-1}"
VERIFY_STATE="${CLAWBAR_VERIFY_OPENCLAW_STATE:-installed}"
RESTART_APP="${CLAWBAR_VERIFY_RESTART:-1}"

cd "$CLAWBAR_MENUBAR_ROOT_DIR"

clawbar_menubar_ensure_ui_app_running "$LAUNCH_WAIT" "${CLAWBAR_VERIFY_BUILD:-1}" "$RESTART_APP" "$VERIFY_STATE"

clawbar_menubar_press_status_item "$APP_NAME" "$ITEM_TITLE" >/dev/null

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
        --expect "Provider 已配置 · Gateway 可达 · Channel 已就绪"
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

clawbar_menubar_verify_popup "${VERIFY_ARGS[@]}"
