#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Lino"
INSTALL_DIR="/Applications"
BUILT_APP=".build/arm64-apple-macosx/debug/$APP_NAME.app"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"

cd "$(dirname "$0")"

echo "Building $APP_NAME..."
swift build

# Quit running instance if any
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    echo "Stopping running $APP_NAME..."
    pkill -x "$APP_NAME"
    sleep 0.5
fi

# Replace installed app
if [ -d "$INSTALLED_APP" ]; then
    echo "Replacing $INSTALLED_APP..."
    rm -rf "$INSTALLED_APP"
fi

echo "Installing to $INSTALL_DIR..."
cp -R "$BUILT_APP" "$INSTALLED_APP"

echo "Launching $APP_NAME..."
open "$INSTALLED_APP"

echo "Done."
