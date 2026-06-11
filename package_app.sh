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

if pgrep -x "$APP_NAME" > /dev/null; then
    echo "WARNING: $APP_NAME is currently running. Replacing the bundle under a"
    echo "         running instance leaves it with stale resources (and can crash"
    echo "         it when it next loads one). Quit it before launching the new build."
fi

# Assemble the bundle in a staging directory and swap it in atomically at the
# end, so a running or mid-launch instance never sees a half-copied bundle.
STAGING="$APP_NAME.app.staging"
echo "Creating $APP_NAME.app bundle..."
rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS"
mkdir -p "$STAGING/Contents/Resources"

# Copy binary
cp "$BINARY_PATH" "$STAGING/Contents/MacOS/$APP_NAME"

# Copy Icon if it exists
if [ -f "Airakeet.icns" ]; then
    cp "Airakeet.icns" "$STAGING/Contents/Resources/"
    ICON_ENTRY="<key>CFBundleIconFile</key><string>Airakeet</string>"
else
    ICON_ENTRY=""
fi

# CRITICAL FIX: Copy dependency resource bundles to prevent crashes in Bundle.module
echo "Embedding resource bundles..."
find "$BUILD_DIR" -name "*.bundle" -maxdepth 1 -exec cp -R {} "$STAGING/Contents/Resources/" \;

# Create Info.plist
cat > "$STAGING/Contents/Info.plist" <<EOF
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
codesign --force --deep --sign - "$STAGING"

# Atomic swap: the fully-assembled, signed bundle replaces the old one in one move.
rm -rf "$APP_NAME.app"
mv "$STAGING" "$APP_NAME.app"

echo "Done! Created $APP_NAME.app in the current directory."
echo "--------------------------------------------------------"
echo "INSTRUCTIONS:"
echo "1. Open System Settings > Privacy & Security > Accessibility"
echo "2. Drag '$APP_NAME.app' from this folder into the Accessibility list."
echo "3. Do the same for Microphone permissions if prompted."
echo "4. Double-click '$APP_NAME.app' to run it."
echo "--------------------------------------------------------"
