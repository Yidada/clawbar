clawbar_menubar_resolve_path() {
    local script_path="$1"

    while [[ -L "$script_path" ]]; do
        local link_target
        link_target="$(readlink "$script_path")"
        if [[ "$link_target" = /* ]]; then
            script_path="$link_target"
        else
            local script_dir
            script_dir="$(cd "$(dirname "$script_path")" && pwd)"
            script_path="$(cd "$script_dir" && cd "$(dirname "$link_target")" && pwd)/$(basename "$link_target")"
        fi
    done

    printf '%s\n' "$script_path"
}

clawbar_menubar_find_root() {
    local search_dir="$1"

    while [[ "$search_dir" != "/" ]]; do
        if [[ -f "$search_dir/Package.swift" && -d "$search_dir/Sources" ]]; then
            printf '%s\n' "$search_dir"
            return 0
        fi
        search_dir="$(dirname "$search_dir")"
    done

    return 1
}

clawbar_menubar_init() {
    local script_path
    script_path="$(clawbar_menubar_resolve_path "$1")"

    local script_dir
    script_dir="$(cd "$(dirname "$script_path")" && pwd)"

    local root_dir
    root_dir="$(clawbar_menubar_find_root "$script_dir")" || {
        echo "Unable to locate repository root from $script_dir" >&2
        return 1
    }

    CLAWBAR_MENUBAR_ROOT_DIR="$root_dir"
    CLAWBAR_MENUBAR_HELPER_DIR="$root_dir/.agents/skills/clawbar-menubar-screenshot/scripts"
}

clawbar_menubar_ensure_ui_app_running() {
    local launch_wait="$1"
    local build_enabled="$2"
    local restart_enabled="$3"
    local openclaw_state="$4"

    local -a harness_args=(
        app start
        --mode ui
        --wait-seconds "$launch_wait"
        --openclaw-state "$openclaw_state"
    )

    if [[ "$openclaw_state" == "installed" ]]; then
        harness_args+=(
            --openclaw-binary-path /opt/homebrew/bin/openclaw
            --openclaw-detail "Provider 已配置 · Gateway 可达 · Channel 已就绪"
            --openclaw-excerpt "OpenClaw 2026.4.2"
        )
    fi

    if [[ "$build_enabled" == "0" ]]; then
        harness_args+=(--no-build)
    fi

    if [[ "$restart_enabled" == "1" ]]; then
        harness_args+=(--restart)
    fi

    local status_output
    status_output="$(python3 "$CLAWBAR_MENUBAR_ROOT_DIR/Tests/Harness/clawbarctl.py" app status 2>/dev/null || true)"

    if [[ "$restart_enabled" == "1" || "$status_output" != *"state: running"* ]]; then
        python3 "$CLAWBAR_MENUBAR_ROOT_DIR/Tests/Harness/clawbarctl.py" "${harness_args[@]}" >/dev/null
    fi
}

clawbar_menubar_press_status_item() {
    swift "$CLAWBAR_MENUBAR_HELPER_DIR/press_status_item.swift" \
        --app-name "$1" \
        --item-title "$2"
}

clawbar_menubar_verify_popup() {
    swift "$CLAWBAR_MENUBAR_HELPER_DIR/verify_popup.swift" "$@"
}
