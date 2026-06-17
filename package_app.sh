#!/bin/bash

# exit on error
set -e

APP_NAME="Airakeet"
BUNDLE_ID="com.cyne-wulf.airakeet"
APP_VERSION="1.6.1"

# Code signing / notarization.
#   SIGN_IDENTITY  - "Developer ID Application" matches the (single) Developer ID
#                    cert in the login keychain by prefix; override with the full
#                    "Developer ID Application: Name (TEAMID)" if you have several.
#   NOTARY_PROFILE - notarytool keychain profile created once via:
#                    xcrun notarytool store-credentials "AirakeetNotary" \
#                      --apple-id <id> --team-id <TEAMID> --password <app-specific-pw>
# Signing with a STABLE Developer ID is what lets macOS keep the Accessibility
# (TCC) grant across updates — ad-hoc signing changes the designated requirement
# every build, so each update looks like a brand-new app and the grant is lost.
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AirakeetNotary}"

# Build for arm64 (Apple Silicon) with xcodebuild — NOT `swift build`.
# `swift build` makes each dependency's generated `Bundle.module` accessor resolve
# resources from Bundle.main.bundleURL (the .app ROOT, which can't hold code-signed
# content) plus a hardcoded build-dir path that only exists on this machine. That is
# why resource-bearing deps like KeyboardShortcuts launched fine here but crashed
# instantly on every other Mac. xcodebuild generates the app-style accessor that
# checks Bundle.main.resourceURL (Contents/Resources) first, so the embedded bundle
# is found on any machine.
echo "Building $APP_NAME in release mode (Apple Silicon) via xcodebuild..."
DERIVED_DATA=".xcode-build"
rm -rf "$DERIVED_DATA"
xcodebuild -scheme "$APP_NAME" -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    build

BUILD_DIR="$DERIVED_DATA/Build/Products/Release"
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
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
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

# Prefer a stable Developer ID identity so the Accessibility grant survives
# updates; fall back to ad-hoc (with a loud warning) so the script still builds
# before the certificate is installed. No --deep: the bundle has no nested
# signable code (the one embedded *.bundle is a resource bundle), and --deep is
# deprecated and unsafe for notarization.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
    DEVID_SIGNED=1
    echo "Signing $APP_NAME.app with Developer ID (hardened runtime)..."
    codesign --force --options runtime --timestamp \
        --entitlements Airakeet.entitlements \
        --sign "$SIGN_IDENTITY" "$STAGING"
else
    DEVID_SIGNED=0
    echo "WARNING: no 'Developer ID Application' identity found — falling back to ad-hoc."
    echo "         This build will LOSE the Accessibility permission on every update."
    echo "         Install a Developer ID cert and re-run to fix this permanently."
    codesign --force --sign - "$STAGING"
fi
codesign --verify --strict --verbose=2 "$STAGING"

# Atomic swap: the fully-assembled, signed bundle replaces the old one in one move.
rm -rf "$APP_NAME.app"
mv "$STAGING" "$APP_NAME.app"

# Notarize + staple so Gatekeeper opens the download without the "unidentified
# developer / cannot check for malware" warning. The stapled ticket lives inside
# the bundle, so it travels with UpdateManager's in-place ditto replace.
# Skipped automatically for ad-hoc builds. `if ...; then` keeps `set -e` from
# aborting the whole script if notarization isn't set up yet.
NOTARIZED=0
if [ "$DEVID_SIGNED" -eq 1 ]; then
    echo "Notarizing $APP_NAME.app (profile: $NOTARY_PROFILE)..."
    ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip"
    if xcrun notarytool submit "$APP_NAME.zip" --keychain-profile "$NOTARY_PROFILE" --wait; then
        xcrun stapler staple "$APP_NAME.app"
        NOTARIZED=1
        echo "Notarized and stapled."
    else
        echo "WARNING: notarization failed or profile '$NOTARY_PROFILE' is not set up."
        echo "         The app is Developer ID signed (permissions WILL persist across"
        echo "         updates), but users will see a Gatekeeper warning on first open."
        echo "         Set up notarytool, then re-run:"
        echo "           xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
        echo "             --apple-id <id> --team-id <TEAMID> --password <app-specific-pw>"
    fi
    # (Re)build the distribution zip from the final (stapled, if successful) bundle.
    rm -f "$APP_NAME.zip"
    ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip"
fi

echo "Done! Created $APP_NAME.app in the current directory."
echo "--------------------------------------------------------"
if [ "$NOTARIZED" -eq 1 ]; then
    echo "Signed with Developer ID and notarized."
    echo "Distribute '$APP_NAME.zip' (carries the stapled notarization ticket)."
    echo "Existing users updating to this build re-grant Accessibility ONE last time;"
    echo "all later updates keep the permission automatically."
elif [ "$DEVID_SIGNED" -eq 1 ]; then
    echo "Signed with Developer ID (NOT notarized — see warning above)."
    echo "Accessibility permission will persist across future updates."
else
    echo "AD-HOC build (no Developer ID identity). Accessibility permission will NOT"
    echo "persist across updates. INSTRUCTIONS:"
    echo "1. Open System Settings > Privacy & Security > Accessibility"
    echo "2. Drag '$APP_NAME.app' from this folder into the Accessibility list."
    echo "3. Do the same for Microphone permissions if prompted."
    echo "4. Double-click '$APP_NAME.app' to run it."
fi
echo "--------------------------------------------------------"
