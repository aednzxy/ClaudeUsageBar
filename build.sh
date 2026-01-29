#!/bin/bash

# Build script for ClaudeUsageBar

set -e

echo "Building ClaudeUsageBar..."

cd "$(dirname "$0")"

# Build using xcodebuild (Apple Silicon only)
xcodebuild -project ClaudeUsageBar.xcodeproj \
    -scheme ClaudeUsageBar \
    -configuration Release \
    -arch arm64 \
    -derivedDataPath build \
    build

# Copy to Applications (optional)
APP_PATH="build/Build/Products/Release/ClaudeUsageBar.app"

if [ -d "$APP_PATH" ]; then
    echo ""
    echo "Build successful!"
    echo "App location: $APP_PATH"
    echo ""
    echo "To install to Applications folder, run:"
    echo "  cp -r \"$APP_PATH\" /Applications/"
    echo ""
    echo "To run immediately:"
    echo "  open \"$APP_PATH\""
else
    echo "Build may have failed - app not found at expected location"
    exit 1
fi
