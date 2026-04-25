#!/bin/zsh
set -euo pipefail

APP_PATH="${APP_PATH:?APP_PATH is required}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:?SIGNING_IDENTITY is required}"
KEYCHAIN_PATH="${KEYCHAIN_PATH:-}"

SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/B"

sign() {
  local path="$1"
  local args=(--force --options runtime --timestamp --sign "$SIGNING_IDENTITY")
  if [[ -n "$KEYCHAIN_PATH" ]]; then
    args+=(--keychain "$KEYCHAIN_PATH")
  fi
  /usr/bin/codesign "${args[@]}" "$path"
}

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  sign "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
  sign "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
  sign "$SPARKLE_VERSION_DIR/Updater.app"
  sign "$SPARKLE_VERSION_DIR/Autoupdate"
  sign "$SPARKLE_FRAMEWORK"
fi

sign "$APP_PATH"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
