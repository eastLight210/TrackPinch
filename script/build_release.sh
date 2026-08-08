#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TrackPinch"
BUNDLE_ID="dev.badgerworks.trackpinch"
VERSION="${TRACKPINCH_VERSION:-0.1.0-alpha.2}"
BUILD_NUMBER="${TRACKPINCH_BUILD_NUMBER:-2}"
ALLOW_ADHOC=0

usage() {
  cat <<'EOF'
usage: ./script/build_release.sh [--version VERSION] [--build-number NUMBER] [--allow-adhoc]

Builds a universal TrackPinch Release app and DMG.

By default, a Developer ID Application identity and NOTARY_PROFILE are required.
Use --allow-adhoc only for an explicitly unnotarized experimental prerelease.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "--version requires a value" >&2; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      [[ $# -ge 2 ]] || { echo "--build-number requires a value" >&2; exit 2; }
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --allow-adhoc)
      ALLOW_ADHOC=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid release version: $VERSION" >&2
  exit 2
fi

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid build number: $BUILD_NUMBER" >&2
  exit 2
fi

MARKETING_VERSION="${VERSION%%-*}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_DIR="$ROOT_DIR/.build/release-universal"
STAGING_DIR="$ROOT_DIR/.build/release-dmg-staging"
NOTARY_ZIP="$ROOT_DIR/.build/$APP_NAME-notary.zip"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST_SOURCE="$ROOT_DIR/Packaging/Info.plist"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo "Stable Xcode developer directory is unavailable: $DEVELOPER_DIR" >&2
  exit 1
fi

export DEVELOPER_DIR

SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
      | /usr/bin/awk '/Developer ID Application/ && !found { print $2; found=1 }'
  )"
fi

IS_ADHOC=0
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  if [[ "$ALLOW_ADHOC" != "1" ]]; then
    echo "An ad hoc identity requires the explicit --allow-adhoc flag." >&2
    exit 1
  fi
  IS_ADHOC=1
elif [[ -z "$SIGNING_IDENTITY" ]]; then
  if [[ "$ALLOW_ADHOC" != "1" ]]; then
    echo "No Developer ID Application identity is available." >&2
    echo "Install one or rerun with --allow-adhoc for an experimental prerelease." >&2
    exit 1
  fi
  SIGNING_IDENTITY="-"
  IS_ADHOC=1
fi

if [[ "$IS_ADHOC" == "0" && -z "${NOTARY_PROFILE:-}" ]]; then
  echo "NOTARY_PROFILE is required for a Developer ID release." >&2
  exit 1
fi

/bin/rm -rf "$APP_BUNDLE" "$STAGING_DIR"
/bin/rm -f "$DMG_PATH" "$CHECKSUM_PATH" "$NOTARY_ZIP"
/bin/mkdir -p "$APP_MACOS" "$STAGING_DIR"

build_args=(
  --package-path "$ROOT_DIR"
  --scratch-path "$SCRATCH_DIR"
  --configuration release
  --arch arm64
  --arch x86_64
)

/usr/bin/xcrun swift build "${build_args[@]}" --product "$APP_NAME"
BUILD_BIN_DIR="$(/usr/bin/xcrun swift build "${build_args[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"

/usr/bin/ditto "$BUILD_BINARY" "$APP_BINARY"
/usr/bin/ditto "$INFO_PLIST_SOURCE" "$APP_CONTENTS/Info.plist"
/bin/chmod +x "$APP_BINARY"

/usr/bin/plutil -replace CFBundleExecutable -string "$APP_NAME" "$APP_CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP_CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$MARKETING_VERSION" "$APP_CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_CONTENTS/Info.plist"
/usr/bin/plutil -replace TrackPinchReleaseVersion -string "$VERSION" "$APP_CONTENTS/Info.plist"

/usr/bin/lipo "$APP_BINARY" -verify_arch arm64 x86_64

codesign_args=(
  --force
  --options runtime
  --sign "$SIGNING_IDENTITY"
)

if [[ "$IS_ADHOC" == "1" ]]; then
  codesign_args+=(--timestamp=none)
else
  codesign_args+=(--timestamp)
fi

/usr/bin/codesign "${codesign_args[@]}" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=4 "$APP_BUNDLE"

if [[ "$IS_ADHOC" == "0" ]]; then
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"
  /usr/bin/xcrun notarytool submit "$NOTARY_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  /usr/bin/xcrun stapler staple "$APP_BUNDLE"
  /usr/bin/xcrun stapler validate "$APP_BUNDLE"
  /usr/sbin/spctl --assess --type execute --verbose=4 "$APP_BUNDLE"
fi

/usr/bin/ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
/usr/bin/ditto "$ROOT_DIR/LICENSE" "$STAGING_DIR/LICENSE.txt"
/bin/ln -s /Applications "$STAGING_DIR/Applications"

if [[ "$IS_ADHOC" == "1" ]]; then
  /usr/bin/printf '%s\n' \
    'TrackPinch experimental alpha' \
    '' \
    'This app is ad hoc signed and not notarized.' \
    'macOS Gatekeeper may block it. Do not disable Gatekeeper globally.' \
    'See the GitHub prerelease notes before installing.' \
    > "$STAGING_DIR/UNSIGNED-ALPHA.txt"
fi

/usr/bin/hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$IS_ADHOC" == "0" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
  /usr/bin/xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  /usr/bin/xcrun stapler staple "$DMG_PATH"
  /usr/bin/xcrun stapler validate "$DMG_PATH"
fi

(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 "$(basename "$DMG_PATH")" \
    > "$(basename "$CHECKSUM_PATH")"
)

echo "Built app: $APP_BUNDLE"
echo "Built DMG: $DMG_PATH"
echo "Checksum: $CHECKSUM_PATH"
echo "Version: $VERSION ($BUILD_NUMBER)"
echo "Architectures: $(/usr/bin/lipo -archs "$APP_BINARY")"
if [[ "$IS_ADHOC" == "1" ]]; then
  echo "Trust: ad hoc signed, not notarized (experimental prerelease)"
else
  echo "Trust: Developer ID signed and notarized"
fi
