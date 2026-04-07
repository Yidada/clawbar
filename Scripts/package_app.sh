#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT_NAME="${PRODUCT_NAME:-Clawbar}"
APP_NAME="${APP_NAME:-${PRODUCT_NAME}.app}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_ROOT="$DIST_DIR/$APP_NAME"
FRAMEWORKS_DIR="$APP_ROOT/Contents/Frameworks"
MACOS_DIR="$APP_ROOT/Contents/MacOS"
RESOURCES_DIR="$APP_ROOT/Contents/Resources"
INFO_PLIST_TEMPLATE="${INFO_PLIST_TEMPLATE:-$ROOT_DIR/Resources/Release/Clawbar-Info.plist}"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
BUNDLE_ID="${BUNDLE_ID:-com.yidada.clawbar}"
APP_VERSION="${APP_VERSION:-$(date -u +"%Y.%m.%d")}"
APP_BUILD="${APP_BUILD:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)}"
GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
ZIP_BASENAME="${ZIP_BASENAME:-${PRODUCT_NAME}-${APP_VERSION}-${APP_BUILD}-${GIT_COMMIT}}"
DMG_BASENAME="${DMG_BASENAME:-${PRODUCT_NAME}-${APP_VERSION}}"
ZIP_PATH="$DIST_DIR/${ZIP_BASENAME}.zip"
DMG_PATH="$DIST_DIR/${DMG_BASENAME}.dmg"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-zip}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-}"
SIGN_WITH_TIMESTAMP="${SIGN_WITH_TIMESTAMP:-0}"

if [[ -n "${BUILD_ARCHS:-}" ]]; then
  BUILD_ARCHS_VALUE="$BUILD_ARCHS"
elif [[ "$BUILD_CONFIG" == "release" ]]; then
  BUILD_ARCHS_VALUE="arm64 x86_64"
else
  BUILD_ARCHS_VALUE="$(uname -m)"
fi
IFS=' ' read -r -a BUILD_ARCH_ARRAY <<< "$BUILD_ARCHS_VALUE"
PRIMARY_ARCH="${BUILD_ARCH_ARRAY[0]}"

build_path_for_arch() {
  printf '%s/.build/release-%s\n' "$ROOT_DIR" "$1"
}

binary_path_for_arch() {
  printf '%s/%s\n' "$(build_path_for_arch "$1")/$BUILD_CONFIG" "$PRODUCT_NAME"
}

codesign_runtime_args=(
  --force
  --options runtime
)
if [[ "$SIGN_WITH_TIMESTAMP" == "1" ]]; then
  codesign_runtime_args+=(--timestamp)
fi

codesign_container_args=(--force)
if [[ "$SIGN_WITH_TIMESTAMP" == "1" ]]; then
  codesign_container_args+=(--timestamp)
fi

if [[ -n "$SIGNING_KEYCHAIN" ]]; then
  codesign_runtime_args+=(--keychain "$SIGNING_KEYCHAIN")
  codesign_container_args+=(--keychain "$SIGNING_KEYCHAIN")
fi

sign_runtime_item() {
  local target="$1"
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    return 0
  fi

  /usr/bin/codesign \
    "${codesign_runtime_args[@]}" \
    --sign "$SIGNING_IDENTITY" \
    "$target"
}

sign_container_item() {
  local target="$1"
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    return 0
  fi

  /usr/bin/codesign \
    "${codesign_container_args[@]}" \
    --sign "$SIGNING_IDENTITY" \
    "$target"
}

verify_output_format() {
  case "$OUTPUT_FORMAT" in
    app|zip|dmg|both)
      ;;
    *)
      echo "Unsupported OUTPUT_FORMAT: $OUTPUT_FORMAT" >&2
      exit 1
      ;;
  esac
}

create_zip() {
  echo "==> Creating zip artifact"
  rm -f "$ZIP_PATH"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_ROOT" "$ZIP_PATH"
  echo "Created zip artifact: $ZIP_PATH"
}

create_dmg() {
  local dmg_staging
  dmg_staging="$(mktemp -d "$DIST_DIR/dmg-staging.XXXXXX")"

  echo "==> Preparing DMG contents"
  cp -R "$APP_ROOT" "$dmg_staging/$APP_NAME"
  ln -s /Applications "$dmg_staging/Applications"

  echo "==> Creating DMG artifact"
  rm -f "$DMG_PATH"
  /usr/bin/hdiutil create \
    -volname "$PRODUCT_NAME" \
    -srcfolder "$dmg_staging" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

  if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "==> Signing DMG"
    sign_container_item "$DMG_PATH"
  fi

  rm -rf "$dmg_staging"
  echo "Created DMG artifact: $DMG_PATH"
}

verify_output_format

mkdir -p "$DIST_DIR"

echo "==> Building $PRODUCT_NAME [$BUILD_CONFIG] for: ${BUILD_ARCH_ARRAY[*]}"
for arch in "${BUILD_ARCH_ARRAY[@]}"; do
  swift build \
    -c "$BUILD_CONFIG" \
    --product "$PRODUCT_NAME" \
    --arch "$arch" \
    --build-path "$(build_path_for_arch "$arch")"
done

BIN_PRIMARY="$(binary_path_for_arch "$PRIMARY_ARCH")"
if [[ ! -f "$BIN_PRIMARY" ]]; then
  echo "Expected binary at $BIN_PRIMARY" >&2
  exit 1
fi

echo "==> Preparing app bundle"
rm -rf "$APP_ROOT"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR"
cp "$INFO_PLIST_TEMPLATE" "$APP_ROOT/Contents/Info.plist"

echo "==> Copying binary"
cp "$BIN_PRIMARY" "$MACOS_DIR/$PRODUCT_NAME"
if (( ${#BUILD_ARCH_ARRAY[@]} > 1 )); then
  BIN_INPUTS=()
  for arch in "${BUILD_ARCH_ARRAY[@]}"; do
    BIN_INPUTS+=("$(binary_path_for_arch "$arch")")
  done
  /usr/bin/lipo -create "${BIN_INPUTS[@]}" -output "$MACOS_DIR/$PRODUCT_NAME"
fi
chmod +x "$MACOS_DIR/$PRODUCT_NAME"

echo "==> Updating Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_ROOT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_ROOT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$APP_ROOT/Contents/Info.plist"

echo "==> Embedding Swift runtime libraries"
/usr/bin/xcrun swift-stdlib-tool \
  --copy \
  --platform macosx \
  --scan-executable "$MACOS_DIR/$PRODUCT_NAME" \
  --destination "$FRAMEWORKS_DIR"

echo "==> Writing build metadata"
cat > "$RESOURCES_DIR/build-info.txt" <<EOF
name=$PRODUCT_NAME
version=$APP_VERSION
build=$APP_BUILD
commit=$GIT_COMMIT
architectures=${BUILD_ARCH_ARRAY[*]}
EOF

if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "==> Signing embedded runtime libraries"
  while IFS= read -r -d '' path; do
    sign_runtime_item "$path"
  done < <(find "$FRAMEWORKS_DIR" -type f -name '*.dylib' -print0)

  echo "==> Signing app bundle"
  sign_runtime_item "$MACOS_DIR/$PRODUCT_NAME"
  sign_runtime_item "$APP_ROOT"
fi

case "$OUTPUT_FORMAT" in
  app)
    ;;
  zip)
    create_zip
    ;;
  dmg)
    create_dmg
    ;;
  both)
    create_zip
    create_dmg
    ;;
esac

echo "Created app bundle: $APP_ROOT"
