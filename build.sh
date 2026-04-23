#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Markdown Reader"
PRODUCT_NAME="MarkdownReader"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
ZIP_FILE="$BUILD_DIR/Markdown-Reader-macOS.zip"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"
ICON_SOURCE="$ROOT_DIR/Assets/AppIconSource.png"
ICON_FILE="$BUILD_DIR/AppIcon.icns"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
rm -f "$ICON_FILE" "$ZIP_FILE"

if [[ -f "$ICON_SOURCE" ]]; then
  python3 "$ROOT_DIR/scripts/generate_icon.py" "$ICON_SOURCE" "$ICON_FILE" >/dev/null
  cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"
fi

clang \
  -isysroot "$SDK_PATH" \
  -target arm64-apple-macos13.0 \
  -fobjc-arc \
  -framework Cocoa \
  -framework WebKit \
  -framework UniformTypeIdentifiers \
  "$ROOT_DIR/App/main.m" \
  -o "$MACOS_DIR/$PRODUCT_NAME"

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_FILE"

echo "Built app:"
echo "$APP_DIR"
echo
echo "Built release zip:"
echo "$ZIP_FILE"
