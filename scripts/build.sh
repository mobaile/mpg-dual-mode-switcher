#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MPG Dual Mode Switcher"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
HELPER_BIN="$ROOT_DIR/dist/mpg-dual-mode-helper"
SHARED_SOURCE="$ROOT_DIR/Sources/MSIHID.swift"
ICON_FILE="$ROOT_DIR/Assets/AppIcon.icns"

rm -rf "$ROOT_DIR/dist"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swiftc \
  -O \
  -target arm64-apple-macosx13.0 \
  -framework IOKit \
  -o "$HELPER_BIN" \
  "$ROOT_DIR/Sources/helper.swift" \
  "$SHARED_SOURCE"

swiftc \
  -O \
  -parse-as-library \
  -target arm64-apple-macosx13.0 \
  -framework SwiftUI \
  -framework AppKit \
  -framework IOKit \
  -o "$MACOS_DIR/$APP_NAME" \
  "$ROOT_DIR/Sources/main.swift" \
  "$SHARED_SOURCE"

cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"
xattr -cr "$APP_DIR" "$HELPER_BIN" 2>/dev/null || true
codesign --force --sign - "$HELPER_BIN"
codesign --force --sign - "$APP_DIR"
COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc --noextattr "$APP_DIR" "$ROOT_DIR/dist/$APP_NAME.zip"

echo "Built: $APP_DIR"
echo "Helper: $HELPER_BIN"
echo "Archive: $ROOT_DIR/dist/$APP_NAME.zip"
