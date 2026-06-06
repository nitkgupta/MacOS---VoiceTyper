#!/bin/bash
set -e

# 1. Setup App Icon
echo "Setting up App Icon..."
ASSETS_DIR="VoiceTyper/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ASSETS_DIR"

# Copy the generated image
ICON_SRC="/Users/nitkarsh.gupta/.gemini/antigravity-cli/brain/d7bd5256-79ad-4335-b153-a07bac0f5c9c/voicetyper_icon_1780758008990.png"
cp "$ICON_SRC" "$ASSETS_DIR/icon-1024.png"

# Write Contents.json for single-size macOS icon
cat << 'JSON' > "$ASSETS_DIR/Contents.json"
{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

# 2. Build the Xcode Project
echo "Building the Xcode project..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

xcodebuild -project VoiceTyper.xcodeproj -scheme VoiceTyper -configuration Release -derivedDataPath build_output clean build > xcodebuild.log 2>&1

if [ $? -ne 0 ]; then
    echo "xcodebuild failed. Check xcodebuild.log"
    cat xcodebuild.log
    exit 1
fi

# Locate the built .app
APP_PATH=$(find build_output -name "VoiceTyper.app" -type d | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "Could not find built VoiceTyper.app"
    exit 1
fi

echo "Found app at: $APP_PATH"

# 3. Create the DMG
echo "Creating DMG..."
DMG_NAME="VoiceTyper.dmg"
DMG_DIR="dmg_staging"

rm -rf "$DMG_DIR"
rm -f "$DMG_NAME"
mkdir -p "$DMG_DIR"

cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create -volname "VoiceTyper" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_NAME" > /dev/null

echo "DMG created successfully at $(pwd)/$DMG_NAME"
