#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_PATH="${1:-$ROOT_DIR/Packaging/AppIconSource.png}"
MASTER_PATH="$ROOT_DIR/Packaging/AppIcon.png"
ICNS_PATH="$ROOT_DIR/Packaging/AppIcon.icns"

if [[ ! -f "$SOURCE_PATH" ]]; then
  echo "App icon source is unavailable: $SOURCE_PATH" >&2
  exit 1
fi

TEMP_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/trackpinch-app-icon.XXXXXX")"
ICONSET_DIR="$TEMP_DIR/AppIcon.iconset"

cleanup() {
  /bin/rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

/bin/mkdir -p "$ICONSET_DIR"
/usr/bin/xcrun swift \
  -module-cache-path "$TEMP_DIR/module-cache" \
  "$ROOT_DIR/script/render_app_icon.swift" \
  "$SOURCE_PATH" \
  "$MASTER_PATH"

render_size() {
  local pixels="$1"
  local filename="$2"

  /usr/bin/sips -z "$pixels" "$pixels" "$MASTER_PATH" \
    --out "$ICONSET_DIR/$filename" >/dev/null
}

render_size 16 icon_16x16.png
render_size 32 icon_16x16@2x.png
render_size 32 icon_32x32.png
render_size 64 icon_32x32@2x.png
render_size 128 icon_128x128.png
render_size 256 icon_128x128@2x.png
render_size 256 icon_256x256.png
render_size 512 icon_256x256@2x.png
render_size 512 icon_512x512.png
render_size 1024 icon_512x512@2x.png

/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "Generated: $MASTER_PATH"
echo "Generated: $ICNS_PATH"
