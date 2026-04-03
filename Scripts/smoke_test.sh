#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${1:-$ROOT_DIR/Artifacts/SmokeTests}"
APP_BINARY="$ROOT_DIR/.build/debug/Clawbar"
APP_LOG="$ARTIFACT_DIR/clawbar-smoke.log"
SCREENSHOT_PATH="$ARTIFACT_DIR/hello-world-smoke.png"

mkdir -p "$ARTIFACT_DIR"
cd "$ROOT_DIR"

swift build >/dev/null

APP_PID=""

cleanup() {
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT

CLAWBAR_SMOKE_TEST=1 "$APP_BINARY" >"$APP_LOG" 2>&1 &
APP_PID=$!

WINDOW_ID=""
for _ in {1..40}; do
    WINDOW_ID="$(
        swift -e '
        import CoreGraphics
        import Foundation

        let expectedOwner = "Clawbar"
        let expectedTitle = "Clawbar Smoke Test"
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        if let match = windows.first(where: { window in
            let owner = window[kCGWindowOwnerName as String] as? String
            let title = window[kCGWindowName as String] as? String
            return owner == expectedOwner && title == expectedTitle
        }),
        let id = match[kCGWindowNumber as String] as? NSNumber {
            print(id.intValue)
        }
        ' | tr -d '\n'
    )"

    if [[ -n "$WINDOW_ID" ]]; then
        break
    fi

    sleep 0.5
done

if [[ -z "$WINDOW_ID" ]]; then
    echo "Smoke test window was not found." >&2
    echo "App log:" >&2
    cat "$APP_LOG" >&2
    exit 1
fi

screencapture -x -l "$WINDOW_ID" "$SCREENSHOT_PATH"

if [[ ! -s "$SCREENSHOT_PATH" ]]; then
    echo "Screenshot was not created: $SCREENSHOT_PATH" >&2
    exit 1
fi

echo "Smoke test screenshot saved to $SCREENSHOT_PATH"
echo "Smoke test log saved to $APP_LOG"
