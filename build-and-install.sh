#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Lino"
INSTALL_DIR="/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
RESOURCES="Sources/Lino/Resources"

cd "$(dirname "$0")"

echo "Building $APP_NAME..."
swift build

BINARY=".build/arm64-apple-macosx/debug/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "Error: binary not found at $BINARY" >&2
    exit 1
fi

# Quit running instance if any
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    echo "Stopping running $APP_NAME..."
    pkill -x "$APP_NAME"
    sleep 0.5
fi

# Assemble .app bundle in a temp location
STAGE=$(mktemp -d)
BUNDLE="$STAGE/$APP_NAME.app"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BINARY" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "$RESOURCES/Info.plist" "$BUNDLE/Contents/"
cp "$RESOURCES/AppIcon.icns" "$BUNDLE/Contents/Resources/"
cp "$RESOURCES"/MenuBarIconTemplate*.png "$BUNDLE/Contents/Resources/" 2>/dev/null || true

# Copy SPM bundled resources if present
RESOURCE_BUNDLE=".build/arm64-apple-macosx/debug/Lino_Lino.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$BUNDLE/Contents/Resources/"
fi

# Replace installed app
if [ -d "$INSTALLED_APP" ]; then
    echo "Replacing $INSTALLED_APP..."
    rm -rf "$INSTALLED_APP"
fi

echo "Installing to $INSTALL_DIR..."
mv "$BUNDLE" "$INSTALLED_APP"
rm -rf "$STAGE"

echo "Launching $APP_NAME..."
open "$INSTALLED_APP"

echo "Done."
