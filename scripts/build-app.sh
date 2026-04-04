#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
RELEASE_DIR="$BUILD_DIR/release"
APP_DIR="$RELEASE_DIR/PrismWindow.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"
SOURCE_ICON="$ROOT_DIR/Resources/AppIcon.png"
PLIST_TEMPLATE="$ROOT_DIR/Resources/Info.plist"

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Missing source icon: $SOURCE_ICON" >&2
  exit 1
fi

if [[ ! -f "$PLIST_TEMPLATE" ]]; then
  echo "Missing Info.plist template: $PLIST_TEMPLATE" >&2
  exit 1
fi

swift build -c release

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

create_icon() {
  local size="$1"
  local name="$2"
  sips -s format png -z "$size" "$size" "$SOURCE_ICON" --out "$ICONSET_DIR/$name" >/dev/null
}

create_icon 16 icon_16x16.png
create_icon 32 icon_16x16@2x.png
create_icon 32 icon_32x32.png
create_icon 64 icon_32x32@2x.png
create_icon 128 icon_128x128.png
create_icon 256 icon_128x128@2x.png
create_icon 256 icon_256x256.png
create_icon 512 icon_256x256@2x.png
create_icon 512 icon_512x512.png
create_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

cp "$RELEASE_DIR/PrismWindow" "$MACOS_DIR/PrismWindow"
cp "$PLIST_TEMPLATE" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/PrismWindow"

codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "Built app bundle: $APP_DIR"
