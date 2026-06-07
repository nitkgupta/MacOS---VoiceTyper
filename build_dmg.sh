#!/bin/bash
set -e

echo "🎙️  Building VoiceTyper Release..."

# Set the active developer directory if needed
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Create a clean build directory
BUILD_DIR="$(pwd)/build"
rm -rf "$BUILD_DIR"

# Build the Xcode Project
echo "Compiling the Xcode project..."
xcodebuild -project VoiceTyper.xcodeproj -scheme VoiceTyper -configuration Release build CONFIGURATION_BUILD_DIR="$BUILD_DIR" > /dev/null

if [ ! -d "$BUILD_DIR/VoiceTyper.app" ]; then
    echo "❌ Build failed or VoiceTyper.app not found."
    exit 1
fi

echo "✅ Build successful!"

# Create the DMG Staging Directory
echo "📦 Packaging DMG..."
DMG_NAME="VoiceTyper.dmg"
DMG_DIR="dmg_staging"

rm -rf "$DMG_DIR"
rm -f "$DMG_NAME"
mkdir -p "$DMG_DIR"

# Copy App and create Applications symlink for drag-and-drop
cp -R "$BUILD_DIR/VoiceTyper.app" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

# Generate the DMG
hdiutil create -volname "VoiceTyper" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_NAME" > /dev/null

# Clean up
rm -rf "$DMG_DIR"
rm -rf "$BUILD_DIR"

echo "🎉 DMG created successfully at: $(pwd)/$DMG_NAME"
