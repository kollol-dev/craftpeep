#!/usr/bin/env bash
# Builds the Release app and wraps it in a DMG. Run from the repo root:
#   ./scripts/build-dmg.sh
# Local use only: the app is not notarised, so other Macs will show Gatekeeper warnings.
set -euo pipefail

APP_NAME="CraftPeep"
PROJECT="App/${APP_NAME}/${APP_NAME}.xcodeproj"
SCHEME="${APP_NAME}"
BUILD_DIR="build"
STAGING="dmg-staging"
DMG="${APP_NAME}.dmg"

if [ ! -d "$PROJECT" ]; then
  echo "Project not found at $PROJECT. Run this script from the repo root." >&2
  exit 1
fi

echo "==> Building Release"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR" build

APP_PATH="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Creating DMG"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "==> Done: $DMG"
echo "Open it, drag ${APP_NAME} into Applications, then launch."
echo "If macOS blocks it: System Settings > Privacy & Security > Open Anyway,"
echo "or: xattr -dr com.apple.quarantine /Applications/${APP_NAME}.app"