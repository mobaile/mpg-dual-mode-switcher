#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MPG Dual Mode Switcher"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

rm -rf "$ROOT_DIR/dist"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swiftc \
  -O \
  -target arm64-apple-macosx13.0 \
  -framework IOKit \
  -o "$MACOS_DIR/mpg-dual-mode-helper" \
  "$ROOT_DIR/Sources/helper.swift"

swiftc \
  -O \
  -parse-as-library \
  -target arm64-apple-macosx13.0 \
  -framework SwiftUI \
  -framework AppKit \
  -o "$MACOS_DIR/$APP_NAME" \
  "$ROOT_DIR/Sources/main.swift"

cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"
ditto -c -k --keepParent "$APP_DIR" "$ROOT_DIR/dist/$APP_NAME.zip"

echo "Built: $APP_DIR"
echo "Archive: $ROOT_DIR/dist/$APP_NAME.zip"
