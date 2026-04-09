#!/bin/bash

# --- 1. Configuration ---
APP_NAME="HushScribe"
IDENTIFIER="com.drcursor.hushscribe"
# The exact string from 'security find-identity'
DEVELOPER_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}')
# The name you gave to 'notarytool store-credentials'
PROFILE_NAME="HushScribe"

# Paths
ROOT_DIR="$(pwd)"
SWIFT_DIR="$ROOT_DIR/HushScribe"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
DMG_NAME="dist/${APP_NAME}.dmg"
ENTITLEMENTS="$SWIFT_DIR/Sources/HushScribe/HushScribe.entitlements"
BINARY_PATH=".build/release/HushScribe"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
ICON_PATH="$SWIFT_DIR/Sources/HushScribe/Assets/AppIcon.icns"
CASK="$ROOT_DIR/Casks/hushscribe.rb"

mkdir -p "$APP_DIR/Contents/MacOS"

cd "$SWIFT_DIR"
swift build -c release 2>&1
BINARY_PATH=".build/release/HushScribe"

if [[ ! -f "$BINARY_PATH" ]]; then
  echo "Build failed: binary not found at $BINARY_PATH"
  exit 1
fi

echo "--- Step 1: Cleaning up old builds ---"
rm -f "$DMG_NAME"
rm -rf "$APP_BUNDLE"

echo "--- Step 2: Creating .app Structure ---"
# Re-assemble your app here. Adjust 'cp' commands as needed.
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"
# Assuming your binary is already compiled in the current folder:
cp "$BINARY_PATH" "$CONTENTS/MacOS/HushScribe"

chmod +x "$CONTENTS/MacOS/$APP_NAME"

if [[ -f "$ICON_PATH" ]]; then
  cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  echo "App icon copied"
fi


cp "$SWIFT_DIR/Sources/HushScribe/Info.plist" "$CONTENTS/Info.plist"

echo "--- Step 3: Deep Signing with Hardened Runtime ---"
# We sign every .dylib and .framework first, then the main app.
find "$APP_BUNDLE" -type f \( -name "*.dylib" -o -name "*.framework" -o -name "*.so" \) -print0 | xargs -0 -I {} \
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "{}"

echo "Signing main executable and bundle..."

codesign --force --options runtime --timestamp \
         --entitlements "$ENTITLEMENTS" \
         --sign "$DEVELOPER_ID" \
         "$APP_BUNDLE"



echo "--- Step 4: Building and Signing DMG ---"
cd $ROOT_DIR
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_NAME"

echo "Signing DMG..."
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG_NAME"

# Exit script for local testing
if [[ "$1" == "test" ]]; then
    echo "Test argument detected. Not notarizing or releasing."
    exit 0
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" dist/HushScribe.app/Contents/Info.plist)

# Check gh release list
if gh release list | grep -q -w v"$VERSION"; then
    echo "Version $VERSION already exists on GitHub. Skipping notarization, release and cask update."
    exit 0
fi

echo "Version $VERSION not found. Proceeding with notarization, release and cask update..."


echo "--- Step 5: Notarization ---"
# Using the static keychain profile
SUBMISSION_INFO=$(xcrun notarytool submit "$DMG_NAME" --keychain-profile "$PROFILE_NAME" --wait)
echo "$SUBMISSION_INFO"

# Check if submission was successful
if [[ "$SUBMISSION_INFO" == *"status: Accepted"* ]]; then
    echo "--- Step 6: Stapling ---"
    xcrun stapler staple "$DMG_NAME"
    echo "Success! $DMG_NAME is ready."
else
    echo "Notarization Failed. Check logs."
    # Extract Submission ID and show log
    SUB_ID=$(echo "$SUBMISSION_INFO" | grep -oE '[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}')
    xcrun notarytool log "$SUB_ID" --keychain-profile "$PROFILE_NAME"
    exit 1
fi


echo "--- Step 6: GH release ---"
gh release create v$VERSION \
    dist/HushScribe.dmg \
    --title "HushScribe v$VERSION" \
    --notes "Release v$VERSION"
echo "Created GH release"


echo "--- Step 7: Update cask ---"
SHA=$(shasum -a 256 dist/HushScribe.dmg | awk '{print $1}')

sed -i '' "s/version \".*\"/version \"$VERSION\"/" "$CASK"
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA\"/" "$CASK"

git commit -m "bump cask" Casks/hushscribe.rb && git push

echo "Updated cask to version $VERSION with sha256 $SHA"

