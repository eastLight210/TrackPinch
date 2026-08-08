#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="TrackPinch"
BUNDLE_ID="dev.badgerworks.trackpinch"
XCODE_VARIANT="${TRACKPINCH_XCODE:-beta}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST_SOURCE="$ROOT_DIR/Packaging/Info.plist"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  case "$XCODE_VARIANT" in
    beta)
      DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
      ;;
    stable)
      DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
      ;;
    *)
      echo "TRACKPINCH_XCODE must be 'beta' or 'stable'" >&2
      exit 2
      ;;
  esac
fi

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo "Xcode developer directory is unavailable: $DEVELOPER_DIR" >&2
  exit 1
fi

export DEVELOPER_DIR
SCRATCH_DIR="$ROOT_DIR/.build/$XCODE_VARIANT"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

/usr/bin/xcrun swift build \
  --package-path "$ROOT_DIR" \
  --scratch-path "$SCRATCH_DIR" \
  --product "$APP_NAME"

BUILD_BIN_DIR="$(
  /usr/bin/xcrun swift build \
    --package-path "$ROOT_DIR" \
    --scratch-path "$SCRATCH_DIR" \
    --show-bin-path
)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$INFO_PLIST_SOURCE" "$APP_CONTENTS/Info.plist"
chmod +x "$APP_BINARY"

SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
SIGNING_KIND="explicit"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
      | /usr/bin/awk '/Developer ID Application/ && !found { print $2; found=1 }'
  )"
  SIGNING_KIND="Developer ID Application"
fi

if [[ -z "$SIGNING_IDENTITY" && "${TRACKPINCH_LOCAL_DEVELOPMENT:-0}" == "1" ]]; then
  SIGNING_IDENTITY="$(
    /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
      | /usr/bin/awk '/Apple Development/ && !/CSSMERR|REVOKED/ && !found { print $2; found=1 }'
  )"
  SIGNING_KIND="Apple Development"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
  SIGNING_KIND="ad hoc"
fi

codesign_args=(
  --force
  --options runtime
  --sign "$SIGNING_IDENTITY"
)

if [[ "$SIGNING_KIND" == "Developer ID Application" || "${TRACKPINCH_TIMESTAMP:-0}" == "1" ]]; then
  codesign_args+=(--timestamp)
else
  codesign_args+=(--timestamp=none)
fi

/usr/bin/codesign "${codesign_args[@]}" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
echo "Bundle ID: $BUNDLE_ID"
echo "Toolchain: $(/usr/bin/xcodebuild -version | tr '\n' ' ')"
echo "macOS SDK: $(/usr/bin/xcrun --sdk macosx --show-sdk-version)"
echo "Signing: $SIGNING_KIND"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

gatekeeper_preflight() {
  local assessment

  if ! assessment="$(/usr/sbin/spctl --assess --type execute --verbose=4 "$APP_BUNDLE" 2>&1)"; then
    echo "$assessment" >&2
    echo "Refusing to launch: Gatekeeper did not approve $APP_BUNDLE" >&2
    echo "Use --build-only until a trusted Developer ID signature and notarization are available." >&2
    return 1
  fi

  echo "$assessment"
}

local_development_preflight() {
  local identity_line

  identity_line="$(
    /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
      | /usr/bin/awk -v identity="$SIGNING_IDENTITY" 'index($0, identity) && !found { print; found=1 }'
  )"

  if [[ -z "$identity_line" || "$identity_line" == *CSSMERR* || "$identity_line" == *REVOKED* ]]; then
    echo "Refusing to launch: the selected Apple Development identity is missing or untrusted." >&2
    return 1
  fi

  if /usr/bin/xattr -p com.apple.quarantine "$APP_BUNDLE" >/dev/null 2>&1; then
    echo "Refusing to launch: the local development bundle is quarantined." >&2
    return 1
  fi

  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
  echo "Local development signature accepted."
}

launch_preflight() {
  local authority

  authority="$(
    /usr/bin/codesign -dvvv "$APP_BUNDLE" 2>&1 \
      | /usr/bin/awk -F= '/^Authority=/ && !found { print substr($0, index($0, "=") + 1); found=1 }'
  )"

  case "$authority" in
    "Developer ID Application:"*)
      gatekeeper_preflight
      ;;
    "Apple Development:"*)
      local_development_preflight
      ;;
    *)
      echo "Refusing to launch: unsupported signing authority '${authority:-none}'." >&2
      return 1
      ;;
  esac
}

case "$MODE" in
  run)
    launch_preflight
    open_app
    ;;
  --build-only|build-only)
    ;;
  --debug|debug)
    launch_preflight
    /usr/bin/xcrun lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    launch_preflight
    open_app
    /usr/bin/log stream \
      --info \
      --style compact \
      --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    launch_preflight
    open_app
    /usr/bin/log stream \
      --info \
      --debug \
      --style compact \
      --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    launch_preflight
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "$APP_NAME is running"
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
