#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
RELEASE_DIR="$BUILD_DIR/release"
APP_DIR="$RELEASE_DIR/Prism Window.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"
SOURCE_ICON="$ROOT_DIR/Resources/AppIcon.png"
PLIST_TEMPLATE="$ROOT_DIR/Resources/Info.plist"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
SKIP_CODESIGN="${SKIP_CODESIGN:-false}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"

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
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

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
cp "$PLIST_TEMPLATE" "$PLIST_PATH"
chmod +x "$MACOS_DIR/PrismWindow"

SPARKLE_FRAMEWORK="$(find "$BUILD_DIR" -path "*/Sparkle.framework" -type d | head -n 1)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "Missing Sparkle.framework in SwiftPM build artifacts" >&2
  exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"

set_plist_string() {
  local key="$1"
  local value="$2"

  if /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST_PATH" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$PLIST_PATH"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$PLIST_PATH"
  fi
}

if [[ -n "$VERSION" ]]; then
  set_plist_string "CFBundleShortVersionString" "$VERSION"
fi

if [[ -n "$BUILD_NUMBER" ]]; then
  set_plist_string "CFBundleVersion" "$BUILD_NUMBER"
fi

if [[ -n "$SPARKLE_FEED_URL" ]]; then
  set_plist_string "SUFeedURL" "$SPARKLE_FEED_URL"
fi

if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  set_plist_string "SUPublicEDKey" "$SPARKLE_PUBLIC_ED_KEY"
fi

if [[ "$SKIP_CODESIGN" != "true" ]]; then
  codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DIR" >/dev/null
fi

echo "Built app bundle: $APP_DIR"
