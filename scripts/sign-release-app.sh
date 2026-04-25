#!/bin/zsh
set -euo pipefail

APP_PATH="${APP_PATH:?APP_PATH is required}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:?SIGNING_IDENTITY is required}"

SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/B"

sign() {
  local path="$1"
  local args=(--force --options runtime --timestamp --sign "$SIGNING_IDENTITY")
  /usr/bin/codesign "${args[@]}" "$path"
}

remove_signature() {
  local path="$1"
  /usr/bin/codesign --remove-signature "$path" >/dev/null 2>&1 || true
}

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

rm -f "$APP_PATH/Contents/CodeResources"

if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  remove_signature "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
  sign "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
  remove_signature "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
  sign "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
  remove_signature "$SPARKLE_VERSION_DIR/Updater.app"
  sign "$SPARKLE_VERSION_DIR/Updater.app"
  remove_signature "$SPARKLE_VERSION_DIR/Autoupdate"
  sign "$SPARKLE_VERSION_DIR/Autoupdate"
  rm -f "$SPARKLE_FRAMEWORK/Versions/B/CodeResources"
  remove_signature "$SPARKLE_FRAMEWORK"
  sign "$SPARKLE_FRAMEWORK"
fi

remove_signature "$APP_PATH"
sign "$APP_PATH"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
