#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/Artifacts/DevRunner"
APP_LOG="$ARTIFACT_DIR/clawbar-dev.log"
POLL_INTERVAL="${CLAWBAR_DEV_POLL_INTERVAL:-1}"

mkdir -p "$ARTIFACT_DIR"
cd "$ROOT_DIR"

APP_BINARY_REAL="$(
    python3 - <<'PY'
from pathlib import Path
print(Path(".build/debug/Clawbar").resolve())
PY
)"
APP_PID=""

fingerprint() {
    python3 - "$ROOT_DIR" <<'PY'
import hashlib
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
watch_roots = [root / "Package.swift", root / "Sources", root / "Tests"]
entries = []

for watch_root in watch_roots:
    if watch_root.is_file():
        stat = watch_root.stat()
        entries.append(f"{watch_root.relative_to(root)}:{stat.st_mtime_ns}:{stat.st_size}")
        continue

    if watch_root.is_dir():
        for path in sorted(p for p in watch_root.rglob("*") if p.is_file()):
            stat = path.stat()
            entries.append(f"{path.relative_to(root)}:{stat.st_mtime_ns}:{stat.st_size}")

payload = "\n".join(entries).encode("utf-8")
print(hashlib.sha256(payload).hexdigest())
PY
}

running_pids() {
    pgrep -f "$APP_BINARY_REAL" || true
}

stop_app() {
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
        APP_PID=""
        sleep 1
        return
    fi

    local pids
    pids="$(running_pids)"
    if [[ -n "$pids" ]]; then
        kill $pids 2>/dev/null || true
        sleep 1
    fi
}

launch_app() {
    : >"$APP_LOG"
    "$APP_BINARY_REAL" >"$APP_LOG" 2>&1 &
    APP_PID=$!
}

restart_app() {
    stop_app
    launch_app
    echo "[$(date '+%H:%M:%S')] app restarted"
}

cleanup() {
    stop_app
}

trap cleanup EXIT INT TERM

echo "Watching for changes every ${POLL_INTERVAL}s"
echo "App log: $APP_LOG"

last_fingerprint=""

while true; do
    current_fingerprint="$(fingerprint)"

    if [[ "$current_fingerprint" != "$last_fingerprint" ]]; then
        echo "[$(date '+%H:%M:%S')] change detected, building..."

        if swift build >/dev/null; then
            restart_app
        else
            echo "[$(date '+%H:%M:%S')] build failed, waiting for next change"
        fi

        last_fingerprint="$current_fingerprint"
    fi

    sleep "$POLL_INTERVAL"
done
