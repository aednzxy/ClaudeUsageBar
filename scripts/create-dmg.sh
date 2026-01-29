#!/bin/bash
# Creates ClaudeUsageBar DMG for distribution
# Output: ClaudeUsageBar-{version}-arm64.dmg

set -e

cd "$(dirname "$0")/.."

# Get version from Info.plist
VERSION=$(defaults read "$(pwd)/ClaudeUsageBar/Info.plist" CFBundleShortVersionString)
DMG_NAME="ClaudeUsageBar-${VERSION}-arm64.dmg"
APP_NAME="ClaudeUsageBar.app"
APP_PATH="build/Build/Products/Release/${APP_NAME}"

echo "Creating ${DMG_NAME}..."

# Build first if app doesn't exist
if [ ! -d "$APP_PATH" ]; then
    echo "App not found, building first..."
    ./build.sh
fi

# Verify app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Build failed - app not found at $APP_PATH"
    exit 1
fi

# Create staging directory
STAGING_DIR=$(mktemp -d)
echo "Staging directory: $STAGING_DIR"

# Copy app to staging
cp -R "$APP_PATH" "$STAGING_DIR/"

# Create Applications symlink
ln -s /Applications "$STAGING_DIR/Applications"

# Remove old DMG if exists
rm -f "$DMG_NAME"

# Create DMG
hdiutil create -volname "ClaudeUsageBar" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_NAME"

# Cleanup staging
rm -rf "$STAGING_DIR"

echo ""
echo "DMG created: $DMG_NAME"
echo ""
echo "To install:"
echo "  1. Open the DMG"
echo "  2. Drag ClaudeUsageBar to Applications"
echo "  3. Right-click the app and select Open (first launch only)"
