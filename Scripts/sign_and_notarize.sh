#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
PRODUCT_NAME="${PRODUCT_NAME:-Clawbar}"
APP_NAME="${APP_NAME:-${PRODUCT_NAME}.app}"
APP_PATH="$DIST_DIR/$APP_NAME"
VERSION_ENV_PATH="${VERSION_ENV_PATH:-$ROOT_DIR/version.env}"

if [[ -f "$VERSION_ENV_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$VERSION_ENV_PATH"
fi

DEFAULT_APP_VERSION="${MARKETING_VERSION:-$(date -u +"%Y.%m.%d")}"
APP_VERSION="${APP_VERSION:-$DEFAULT_APP_VERSION}"
BUILD_TIME_TAG="${BUILD_TIME_TAG:-$(date -u +"%H_%M_%S")}"
DMG_BASENAME="${DMG_BASENAME:-${PRODUCT_NAME}-${APP_VERSION}}"
DMG_PATH="$DIST_DIR/${DMG_BASENAME}.dmg"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-dmg}"
NOTARIZE="${NOTARIZE:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"
APPLE_NOTARY_API_KEY_PATH="${APPLE_NOTARY_API_KEY_PATH:-}"
TEMP_API_KEY_PATH=""
SPCTL_BIN="${SPCTL_BIN:-$(command -v spctl || true)}"
SYSPOLICY_CHECK_BIN="$(command -v syspolicy_check || true)"

cleanup() {
  if [[ -n "$TEMP_API_KEY_PATH" && -f "$TEMP_API_KEY_PATH" ]]; then
    rm -f "$TEMP_API_KEY_PATH"
  fi
}
trap cleanup EXIT

assess_with_spctl() {
  local target_type="$1"
  local target_path="$2"
  local output

  if output="$("$SPCTL_BIN" --assess --type "$target_type" -vvv "$target_path" 2>&1)"; then
    printf '%s\n' "$output"
    return 0
  fi

  if [[ "$target_type" == "open" && "$output" == *"source=Insufficient Context"* ]]; then
    printf '%s\n' "$output"
    echo "spctl returned 'Insufficient Context' for the DMG open assessment; continuing because codesign and stapler validation succeeded."
    return 0
  fi

  printf '%s\n' "$output" >&2
  return 1
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

ensure_notary_api_key_file() {
  if [[ -n "$APPLE_NOTARY_API_KEY_PATH" ]]; then
    if [[ ! -f "$APPLE_NOTARY_API_KEY_PATH" ]]; then
      echo "APPLE_NOTARY_API_KEY_PATH does not exist: $APPLE_NOTARY_API_KEY_PATH" >&2
      exit 1
    fi
    return 0
  fi

  require_env APPLE_NOTARY_API_KEY_BASE64
  TEMP_API_KEY_PATH="$(mktemp "$DIST_DIR/notary-api-key.XXXXXX")"
  APPLE_NOTARY_API_KEY_BASE64="$APPLE_NOTARY_API_KEY_BASE64" \
  TEMP_API_KEY_PATH="$TEMP_API_KEY_PATH" \
  python3 - <<'PY'
import base64
import os
from pathlib import Path

Path(os.environ["TEMP_API_KEY_PATH"]).write_bytes(
    base64.b64decode(os.environ["APPLE_NOTARY_API_KEY_BASE64"])
)
PY
  APPLE_NOTARY_API_KEY_PATH="$TEMP_API_KEY_PATH"
}

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "SIGNING_IDENTITY is required for signing and notarization." >&2
  exit 1
fi

if [[ -z "$SPCTL_BIN" ]]; then
  echo "spctl is required for local verification but was not found on PATH." >&2
  exit 1
fi

if [[ "$OUTPUT_FORMAT" != "dmg" && "$OUTPUT_FORMAT" != "both" ]]; then
  echo "sign_and_notarize.sh requires OUTPUT_FORMAT=dmg or OUTPUT_FORMAT=both." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"

echo "==> Packaging signed app"
SIGNING_IDENTITY="$SIGNING_IDENTITY" \
SIGNING_KEYCHAIN="$SIGNING_KEYCHAIN" \
SIGN_WITH_TIMESTAMP=1 \
OUTPUT_FORMAT="$OUTPUT_FORMAT" \
DIST_DIR="$DIST_DIR" \
APP_VERSION="$APP_VERSION" \
BUILD_TIME_TAG="$BUILD_TIME_TAG" \
DMG_BASENAME="$DMG_BASENAME" \
"$ROOT_DIR/Scripts/package_app.sh"

if [[ "$NOTARIZE" != "1" ]]; then
  echo "==> Skipping notarization because NOTARIZE=$NOTARIZE"
  exit 0
fi

require_env APPLE_NOTARY_KEY_ID
require_env APPLE_NOTARY_ISSUER_ID
ensure_notary_api_key_file

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Expected DMG artifact at $DMG_PATH" >&2
  exit 1
fi

echo "==> Submitting DMG for notarization"
/usr/bin/xcrun notarytool submit "$DMG_PATH" \
  --key "$APPLE_NOTARY_API_KEY_PATH" \
  --key-id "$APPLE_NOTARY_KEY_ID" \
  --issuer "$APPLE_NOTARY_ISSUER_ID" \
  --wait

echo "==> Stapling notarization tickets"
/usr/bin/xcrun stapler staple "$APP_PATH"
/usr/bin/xcrun stapler staple "$DMG_PATH"

echo "==> Verifying signed app and DMG"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
"$SPCTL_BIN" --assess --type exec -vvv "$APP_PATH"
if [[ -n "$SYSPOLICY_CHECK_BIN" ]]; then
  "$SYSPOLICY_CHECK_BIN" distribution "$DMG_PATH"
else
  "$SPCTL_BIN" --assess --type open -vvv "$DMG_PATH"
fi
/usr/bin/xcrun stapler validate "$APP_PATH"
/usr/bin/xcrun stapler validate "$DMG_PATH"

echo "Signed and notarized artifacts:"
echo "  App: $APP_PATH"
echo "  DMG: $DMG_PATH"
