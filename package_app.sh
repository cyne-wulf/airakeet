#!/bin/bash

# exit on error
set -e

APP_NAME="Airakeet"
BUNDLE_ID="com.cyne-wulf.airakeet"

# Build for arm64 (Apple Silicon)
echo "Building $APP_NAME in release mode (Apple Silicon)..."
swift build -c release --product Airakeet --arch arm64

BUILD_DIR=".build/arm64-apple-macosx/release"
BINARY_PATH="$BUILD_DIR/$APP_NAME"

if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    exit 1
fi

echo "Creating $APP_NAME.app bundle..."
rm -rf "$APP_NAME.app"
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"

# Copy binary
cp "$BINARY_PATH" "$APP_NAME.app/Contents/MacOS/$APP_NAME"

# Copy Icon if it exists
if [ -f "Airakeet.icns" ]; then
    cp "Airakeet.icns" "$APP_NAME.app/Contents/Resources/"
    ICON_ENTRY="<key>CFBundleIconFile</key><string>Airakeet</string>"
else
    ICON_ENTRY=""
fi

# CRITICAL FIX: Copy dependency resource bundles to prevent crashes in Bundle.module
echo "Embedding resource bundles..."
find "$BUILD_DIR" -name "*.bundle" -maxdepth 1 -exec cp -R {} "$APP_NAME.app/Contents/Resources/" \;

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
    <string>1.5.3</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Airakeet needs microphone access to dictate text.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    $ICON_ENTRY
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
