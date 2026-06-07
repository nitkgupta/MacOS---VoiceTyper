#!/bin/bash
set -e

echo "🛠️  Setting up VoiceTyper for development..."

# Check if Xcode Command Line Tools are installed
if ! xcode-select -p &> /dev/null; then
    echo "❌ Xcode Command Line Tools not found. Installing..."
    xcode-select --install
    echo "Please complete the installation prompt and run this script again."
    exit 1
fi

# We use standard Swift Package Manager, so no submodules or xcodegen required!
echo "✅ Environment looks good."

echo "📦 Opening VoiceTyper in Xcode..."
# Open the Xcode project. Xcode will automatically resolve the SwiftWhisper package via SPM.
open VoiceTyper.xcodeproj

echo "🎉 Project is ready for development!"
echo "Note: Wait a few seconds for Xcode to finish 'Resolving Package Graph', then hit Cmd + R to run."
