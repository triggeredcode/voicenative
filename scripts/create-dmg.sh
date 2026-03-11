#!/bin/bash
set -euo pipefail

APP_NAME="VoiceNative"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"
STAGING="$DIST_DIR/dmg-staging"

if [ ! -d "$APP_DIR" ]; then
    echo "ERROR: App bundle not found. Run ./scripts/package-app.sh first."
    exit 1
fi

echo "==> Creating DMG..."
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"

# Symlink to /Applications for drag-and-drop install
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH" 2>&1

rm -rf "$STAGING"

echo ""
echo "==> Created: $DMG_PATH"
echo "    Size: $(du -sh "$DMG_PATH" | cut -f1)"
