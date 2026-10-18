#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
RELEASE_DIR="$BUILD_DIR/release"
APP_DIR="$RELEASE_DIR/Prism Window.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"
SOURCE_ICON="$ROOT_DIR/Resources/AppIcon.png"
PLIST_TEMPLATE="$ROOT_DIR/Resources/Info.plist"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
SIGNING_MODE="${SIGNING_MODE:-adhoc}"

[[ "$SIGNING_MODE" == adhoc || "$SIGNING_MODE" == unsigned ]] || {
  echo "SIGNING_MODE must be adhoc or unsigned; use macos-distribution.py for Developer ID distribution." >&2
  exit 1
}

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Missing source icon: $SOURCE_ICON" >&2
  exit 1
fi

if [[ ! -f "$PLIST_TEMPLATE" ]]; then
  echo "Missing Info.plist template: $PLIST_TEMPLATE" >&2
  exit 1
fi

cd "$ROOT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

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

cp "$BIN_DIR/PrismWindow" "$MACOS_DIR/PrismWindow"
cp "$PLIST_TEMPLATE" "$PLIST_PATH"
mkdir -p "$CONTENTS_DIR/Frameworks"
SPARKLE_FRAMEWORK="$BUILD_DIR/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$SPARKLE_FRAMEWORK" ]] || { echo "Sparkle framework not found: $SPARKLE_FRAMEWORK" >&2; exit 1; }
ditto --norsrc --noextattr "$SPARKLE_FRAMEWORK" "$CONTENTS_DIR/Frameworks/Sparkle.framework"
if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_ED_KEY" "$PLIST_PATH"
fi
if [[ -n "${SPARKLE_FEED_URL:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL $SPARKLE_FEED_URL" "$PLIST_PATH"
fi
chmod +x "$MACOS_DIR/PrismWindow"

if [[ -n "$VERSION" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST_PATH"
fi

if [[ -n "$BUILD_NUMBER" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST_PATH"
fi

if [[ "$SIGNING_MODE" == adhoc ]]; then
  python3 -B "$ROOT_DIR/scripts/macos-distribution.py" sign-local "$APP_DIR"
fi

echo "Built app bundle: $APP_DIR"
