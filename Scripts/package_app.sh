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
ZIP_PATH="$DIST_DIR/${ZIP_BASENAME}.zip"

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

echo "==> Ad-hoc signing app bundle"
/usr/bin/codesign \
  --force \
  --deep \
  --options runtime \
  --sign - \
  "$APP_ROOT"

echo "==> Writing build metadata"
cat > "$RESOURCES_DIR/build-info.txt" <<EOF
name=$PRODUCT_NAME
version=$APP_VERSION
build=$APP_BUILD
commit=$GIT_COMMIT
architectures=${BUILD_ARCH_ARRAY[*]}
EOF

echo "==> Creating zip artifact"
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_ROOT" "$ZIP_PATH"

echo "Created app bundle: $APP_ROOT"
echo "Created zip artifact: $ZIP_PATH"
