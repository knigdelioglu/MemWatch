#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${1:-$ROOT_DIR/build/DerivedData}"
DIST_DIR="${2:-$ROOT_DIR/dist}"
APP_NAME="MemWatch"
APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
STAGE_DIR="$DIST_DIR/dmg-root"
HELPER_PLIST_NAME="com.knigdelioglu.MemWatch.PrivilegedHelper.plist"
HELPER_PLIST_REL="Contents/Library/LaunchDaemons/$HELPER_PLIST_NAME"

rm -rf "$DERIVED_DATA" "$DIST_DIR"
mkdir -p "$DIST_DIR"

xcodebuild \
  -project "$ROOT_DIR/MemWatch.xcodeproj" \
  -scheme MemWatch \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Release app was not produced at $APP_PATH" >&2
  exit 1
fi

BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"
ARCHS_OUTPUT="$(lipo -archs "$BINARY")"
echo "Architectures: $ARCHS_OUTPUT"

if [[ "$ARCHS_OUTPUT" != *"arm64"* || "$ARCHS_OUTPUT" != *"x86_64"* ]]; then
  echo "Release binary is not universal arm64 + x86_64" >&2
  exit 1
fi

verify_helper_bundle() {
  local app="$1"
  local plist="$app/$HELPER_PLIST_REL"
  if [[ ! -f "$plist" ]]; then
    echo "LaunchDaemon plist missing from app bundle: $plist" >&2
    exit 1
  fi
  plutil -lint "$plist" >/dev/null

  local bundle_program
  bundle_program="$(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' "$plist")"
  if [[ -z "$bundle_program" ]]; then
    echo "LaunchDaemon BundleProgram is empty" >&2
    exit 1
  fi

  local helper="$app/$bundle_program"
  if [[ ! -x "$helper" ]]; then
    echo "Privileged helper is missing or not executable: $helper" >&2
    exit 1
  fi

  local helper_archs
  helper_archs="$(lipo -archs "$helper")"
  if [[ "$helper_archs" != *"arm64"* || "$helper_archs" != *"x86_64"* ]]; then
    echo "Privileged helper is not universal arm64 + x86_64: $helper_archs" >&2
    exit 1
  fi

  echo "LaunchDaemon plist: $HELPER_PLIST_REL"
  echo "Privileged helper: $bundle_program ($helper_archs)"
}

# Fail the package before signing if SMAppService would not be able to find its
# LaunchDaemon definition or the BundleProgram it references.
verify_helper_bundle "$APP_PATH"

# Ad-hoc signing makes the CI artifact internally consistent, but it is not
# Developer ID signing and does not replace Apple notarization for distribution.
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

HELPER_BUNDLE_PROGRAM="$(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' "$APP_PATH/$HELPER_PLIST_REL")"
codesign --verify --strict --verbose=2 "$APP_PATH/$HELPER_BUNDLE_PROGRAM"

mkdir -p "$STAGE_DIR"
ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

hdiutil verify "$DMG_PATH"

MOUNT_DIR="$(mktemp -d /tmp/memwatch-dmg.XXXXXX)"
cleanup() {
  hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" -quiet
if [[ ! -d "$MOUNT_DIR/$APP_NAME.app" ]]; then
  echo "DMG mounted but $APP_NAME.app is missing" >&2
  exit 1
fi

# Verify the exact artifact users install, not only DerivedData output.
verify_helper_bundle "$MOUNT_DIR/$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "$MOUNT_DIR/$APP_NAME.app"

hdiutil detach "$MOUNT_DIR" -quiet
trap - EXIT
rmdir "$MOUNT_DIR" || true

shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"

echo "Release package ready: $DMG_PATH"
