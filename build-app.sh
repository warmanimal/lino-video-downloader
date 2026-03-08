#!/bin/bash
set -euo pipefail

# Build Lino.app from the Swift package
# Usage: ./build-app.sh [release|debug]

CONFIG="${1:-debug}"
APP_NAME="Lino"

echo "Building $APP_NAME ($CONFIG)..."

if [ "$CONFIG" = "release" ]; then
    swift build -c release
    BUILD_DIR=".build/release"
else
    swift build
    BUILD_DIR=".build/debug"
fi

BINARY="$BUILD_DIR/$APP_NAME"

if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found at $BINARY"
    exit 1
fi

# Create .app bundle structure
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$BINARY" "$MACOS/$APP_NAME"

# Copy Info.plist
cp "Sources/Lino/Resources/Info.plist" "$CONTENTS/Info.plist"

# Download standalone yt-dlp binary from GitHub releases
YTDLP_RESOURCE="$RESOURCES/yt-dlp"
YTDLP_CACHE=".build/yt-dlp_macos"

if [ -f "$YTDLP_CACHE" ]; then
    echo "Using cached yt-dlp standalone binary"
    cp "$YTDLP_CACHE" "$YTDLP_RESOURCE"
    chmod 755 "$YTDLP_RESOURCE"
else
    echo "Downloading yt-dlp standalone binary from GitHub..."
    DOWNLOAD_URL=$(curl -sL --connect-timeout 10 --max-time 30 \
        https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest \
        | grep -o '"browser_download_url": *"[^"]*yt-dlp_macos"' \
        | head -1 \
        | sed 's/"browser_download_url": *"//' \
        | sed 's/"$//')

    if [ -n "$DOWNLOAD_URL" ]; then
        echo "Downloading from: $DOWNLOAD_URL"
        if curl -L --progress-bar --connect-timeout 10 --max-time 300 -o "$YTDLP_CACHE" "$DOWNLOAD_URL"; then
            chmod 755 "$YTDLP_CACHE"
            # Verify it's a real binary (> 1MB)
            FILE_SIZE=$(wc -c < "$YTDLP_CACHE" | tr -d ' ')
            if [ "$FILE_SIZE" -gt 1000000 ]; then
                echo "Downloaded yt-dlp ($FILE_SIZE bytes)"
                cp "$YTDLP_CACHE" "$YTDLP_RESOURCE"
                chmod 755 "$YTDLP_RESOURCE"
            else
                echo "Warning: Downloaded file too small ($FILE_SIZE bytes), skipping"
                rm -f "$YTDLP_CACHE"
            fi
        else
            echo "Warning: Failed to download yt-dlp. The app will use system yt-dlp if available."
        fi
    else
        echo "Warning: Could not find yt-dlp download URL. The app will use system yt-dlp if available."
    fi
fi

echo ""
echo "Build complete: $APP_DIR"
echo ""
echo "To run:"
echo "  open $APP_DIR"
echo ""
echo "To install:"
echo "  cp -r $APP_DIR /Applications/"
