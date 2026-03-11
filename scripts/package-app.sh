#!/bin/bash
set -euo pipefail

APP_NAME="VoiceNative"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPM_DIR="$PROJECT_ROOT/VoiceNative"
DIST_DIR="$PROJECT_ROOT/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"

echo "==> Building release binary..."
cd "$SPM_DIR"
swift build -c release 2>&1

BINARY="$SPM_DIR/.build/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "==> Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$SPM_DIR/Resources/Info.plist" "$APP_DIR/Contents/"

# Ad-hoc code sign so macOS doesn't complain about unsigned binaries
echo "==> Code signing (ad-hoc)..."
codesign --force --sign - --deep "$APP_DIR"

echo ""
echo "==> Built: $APP_DIR"
echo "    Size: $(du -sh "$APP_DIR" | cut -f1)"
echo ""
echo "Drag $APP_DIR to /Applications to install."
