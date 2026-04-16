#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
NOTARIZE="${CLAWBAR_DMG_NOTARIZE:-0}"
ENV_FILE="${CLAWBAR_DMG_ENV_FILE:-$ROOT_DIR/.env}"

load_local_env() {
  if [[ -f "$ENV_FILE" ]]; then
    echo "Loading packaging environment from $ENV_FILE"
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
}

load_local_env

case "$NOTARIZE" in
  0)
    exec env OUTPUT_FORMAT=dmg "$ROOT_DIR/Scripts/package_app.sh"
    ;;
  1)
    exec env OUTPUT_FORMAT=dmg "$ROOT_DIR/Scripts/sign_and_notarize.sh"
    ;;
  *)
    echo "Unsupported CLAWBAR_DMG_NOTARIZE value: $NOTARIZE" >&2
    echo "Use 0 for local packaging or 1 for signing + notarization." >&2
    exit 1
    ;;
esac
