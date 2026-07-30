#!/bin/bash
set -euo pipefail

VERSION="${1:-v0.0.0}"
BUILD_DIR=".build/release"
APP_NAME="Burn"
APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}-macos.dmg"

BUNDLE_ID="com.maferland.burn"
EXECUTABLE="${BUILD_DIR}/${APP_NAME}"

echo "Packaging ${APP_NAME} ${VERSION}..."

swift build -c release

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${EXECUTABLE}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy Swift Package resource bundles
for bundle in "${BUILD_DIR}"/*.bundle; do
    [ -d "$bundle" ] && cp -R "$bundle" "${APP_BUNDLE}/Contents/Resources/"
done

cat > "${APP_BUNDLE}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if command -v sips &> /dev/null && [ -f "assets/icon.png" ]; then
    ICONSET_DIR="/tmp/${APP_NAME}.iconset"
    rm -rf "${ICONSET_DIR}"
    mkdir -p "${ICONSET_DIR}"

    sips -z 16 16     assets/icon.png --out "${ICONSET_DIR}/icon_16x16.png" 2>/dev/null
    sips -z 32 32     assets/icon.png --out "${ICONSET_DIR}/icon_16x16@2x.png" 2>/dev/null
    sips -z 32 32     assets/icon.png --out "${ICONSET_DIR}/icon_32x32.png" 2>/dev/null
    sips -z 64 64     assets/icon.png --out "${ICONSET_DIR}/icon_32x32@2x.png" 2>/dev/null
    sips -z 128 128   assets/icon.png --out "${ICONSET_DIR}/icon_128x128.png" 2>/dev/null
    sips -z 256 256   assets/icon.png --out "${ICONSET_DIR}/icon_128x128@2x.png" 2>/dev/null
    sips -z 256 256   assets/icon.png --out "${ICONSET_DIR}/icon_256x256.png" 2>/dev/null
    sips -z 512 512   assets/icon.png --out "${ICONSET_DIR}/icon_256x256@2x.png" 2>/dev/null
    sips -z 512 512   assets/icon.png --out "${ICONSET_DIR}/icon_512x512.png" 2>/dev/null
    sips -z 1024 1024 assets/icon.png --out "${ICONSET_DIR}/icon_512x512@2x.png" 2>/dev/null

    iconutil -c icns "${ICONSET_DIR}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    rm -rf "${ICONSET_DIR}"
fi

echo "Created ${APP_BUNDLE}"

: "${SIGN_IDENTITY:=$(security find-identity -p codesigning -v | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
: "${ENTITLEMENTS_FILE:=Burn.entitlements}"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "Signing app bundle with ${SIGN_IDENTITY}..."
    CODESIGN_ARGS=(
        --sign "${SIGN_IDENTITY}"
        --options runtime
        --timestamp
        --deep
        --force
    )
    if [ -f "${ENTITLEMENTS_FILE}" ]; then
        CODESIGN_ARGS+=(--entitlements "${ENTITLEMENTS_FILE}")
    fi
    codesign "${CODESIGN_ARGS[@]}" "${APP_BUNDLE}"
    echo "Signed ${APP_BUNDLE}"
else
    echo "WARN: no Developer ID Application certificate found, skipping signing"
fi

# A keychain profile keeps the app-specific password out of the process list.
# Create one with: xcrun notarytool store-credentials <name> --apple-id ... --team-id ... --password ...
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

can_notarize() {
    [ -n "${NOTARY_PROFILE}" ] ||
        { [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${NOTARIZE_PASSWORD:-}" ]; }
}

notarize() {
    if [ -n "${NOTARY_PROFILE}" ]; then
        echo "Submitting ${1} for notarization (keychain profile ${NOTARY_PROFILE})..."
        xcrun notarytool submit "${1}" --keychain-profile "${NOTARY_PROFILE}" --wait
        return
    fi
    echo "Submitting ${1} for notarization..."
    echo "WARN: passing the password on the command line, where any local process can read it."
    echo "      Set NOTARY_PROFILE to use a keychain profile instead."
    xcrun notarytool submit "${1}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${APPLE_TEAM_ID}" \
        --password "${NOTARIZE_PASSWORD}" \
        --wait
}

# Notarize the app before it goes in the image, so a copy dragged out of the DMG carries its
# own ticket instead of needing Gatekeeper to fetch one.
if can_notarize; then
    ZIP_PATH="/tmp/${APP_NAME}-notarize.zip"
    rm -f "${ZIP_PATH}"
    ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"
    notarize "${ZIP_PATH}"
    rm -f "${ZIP_PATH}"
    echo "Stapling notarization ticket to ${APP_BUNDLE}..."
    xcrun stapler staple "${APP_BUNDLE}"
    xcrun stapler validate "${APP_BUNDLE}"
fi

echo "Creating DMG..."
rm -rf /tmp/Burn-dmg
mkdir -p /tmp/Burn-dmg
cp -R "${APP_BUNDLE}" /tmp/Burn-dmg/
ln -s /Applications /tmp/Burn-dmg/Applications

hdiutil create -volname "Burn ${VERSION}" \
    -srcfolder /tmp/Burn-dmg \
    -ov -format UDZO \
    "${DMG_NAME}"

rm -rf /tmp/Burn-dmg

echo "Created ${DMG_NAME}"

# An attached image makes notarytool's preflight fail its disk-image test and then hang
# indefinitely without ever registering a submission.
detach_image() {
    local image_path
    image_path="$(cd "$(dirname "${1}")" && pwd)/$(basename "${1}")"
    hdiutil info | awk -v img="${image_path}" '
        /^image-path[[:space:]]*:/ {
            path = $0
            sub(/^image-path[[:space:]]*:[[:space:]]*/, "", path)
            mine = (path == img)
        }
        mine && $1 ~ /^\/dev\/disk[0-9]+$/ { print $1 }
    ' | while read -r device; do
        echo "Detaching ${device} (${1} was left attached)"
        hdiutil detach "${device}" -force >/dev/null 2>&1 || true
    done
}
detach_image "${DMG_NAME}"

if ! can_notarize; then
    echo "WARN: no notarization credentials, skipping notarization"
    exit 0
fi

notarize "${DMG_NAME}"

echo "Stapling notarization ticket to ${DMG_NAME}..."
xcrun stapler staple "${DMG_NAME}"
xcrun stapler validate "${DMG_NAME}"

echo "Notarization complete"
