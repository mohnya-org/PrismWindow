#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"

VERSION="${VERSION:?VERSION is required}"
BUILD_NUMBER="${BUILD_NUMBER:?BUILD_NUMBER is required}"
TAG="${TAG:?TAG is required}"
ZIP_PATH="${ZIP_PATH:?ZIP_PATH is required}"
OUTPUT_PATH="${OUTPUT_PATH:?OUTPUT_PATH is required}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
SPARKLE_PRIVATE_KEY_PATH="${SPARKLE_PRIVATE_KEY_PATH:?SPARKLE_PRIVATE_KEY_PATH is required}"
SPARKLE_SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-}"

if [[ -z "$SPARKLE_SIGN_UPDATE" ]]; then
  SPARKLE_SIGN_UPDATE="$(find "$BUILD_DIR" -path "*/bin/sign_update" -type f | head -n 1)"
fi

if [[ -z "$SPARKLE_SIGN_UPDATE" || ! -x "$SPARKLE_SIGN_UPDATE" ]]; then
  echo "Sparkle sign_update tool not found. Run swift build first." >&2
  exit 1
fi

ZIP_NAME="$(basename "$ZIP_PATH")"
URL_ZIP_NAME="${ZIP_NAME// /%20}"
DOWNLOAD_URL="https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/$URL_ZIP_NAME"
SIGNATURE_OUTPUT="$("$SPARKLE_SIGN_UPDATE" -f "$SPARKLE_PRIVATE_KEY_PATH" "$ZIP_PATH")"
ED_SIGNATURE="$(printf '%s\n' "$SIGNATURE_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(printf '%s\n' "$SIGNATURE_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
PUB_DATE="$(date -u "+%a, %d %b %Y %H:%M:%S +0000")"

if [[ -z "$ED_SIGNATURE" || -z "$LENGTH" ]]; then
  echo "Could not parse Sparkle signature output:" >&2
  printf '%s\n' "$SIGNATURE_OUTPUT" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
cat > "$OUTPUT_PATH" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Prism Window Updates</title>
    <link>https://github.com/$GITHUB_REPOSITORY/releases</link>
    <description>Prism Window app updates</description>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure
        url="$DOWNLOAD_URL"
        length="$LENGTH"
        type="application/octet-stream"
        sparkle:edSignature="$ED_SIGNATURE" />
    </item>
  </channel>
</rss>
EOF

echo "Generated Sparkle appcast: $OUTPUT_PATH"
