#!/bin/bash

# exit on error
set -e

APP_NAME="Airakeet"
BUNDLE_ID="com.cyne-wulf.airakeet"
BUILD_PATH=".build/apple/Products/Release" # Default for swift build -c release on macOS
# But wait, swift build usually puts it in .build/release
BINARY_PATH=".build/release/Airakeet"

echo "Building $APP_NAME in release mode..."
swift build -c release --product Airakeet

if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    exit 1
fi

echo "Creating $APP_NAME.app bundle..."
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"

# Copy binary
cp "$BINARY_PATH" "$APP_NAME.app/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat > "$APP_NAME.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Airakeet needs microphone access to dictate text.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Ad-hoc signing $APP_NAME.app..."
codesign --force --deep --sign - "$APP_NAME.app"

echo "Done! Created $APP_NAME.app in the current directory."
echo "--------------------------------------------------------"
echo "INSTRUCTIONS:"
echo "1. Open System Settings > Privacy & Security > Accessibility"
echo "2. Drag '$APP_NAME.app' from this folder into the Accessibility list."
echo "3. Do the same for Microphone permissions if prompted."
echo "4. Double-click '$APP_NAME.app' to run it."
echo "--------------------------------------------------------"
