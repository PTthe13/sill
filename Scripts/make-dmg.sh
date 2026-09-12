#!/bin/bash
# Builds Sill.app and wraps it in a compressed disk image.
#
# Distribution outside the App Store also needs a Developer ID signature and
# notarisation, which this machine has no identity for. Set SILL_SIGN_IDENTITY
# to a "Developer ID Application: ..." identity before running, then notarise:
#   xcrun notarytool submit build/Sill.dmg --keychain-profile <profile> --wait
#   xcrun stapler staple build/Sill.dmg
# Without that, Gatekeeper warns on first open (right-click > Open to bypass).
set -euo pipefail
cd "$(dirname "$0")/.."

./Scripts/build-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
STAGING=build/dmg
DMG="build/Sill-$VERSION.dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R build/Sill.app "$STAGING/Sill.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Sill" -srcfolder "$STAGING" -ov -format UDZO \
    -imagekey zlib-level=9 "$DMG" >/dev/null
rm -rf "$STAGING"

if [[ -n "${SILL_SIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$SILL_SIGN_IDENTITY" "$DMG"
fi

echo "built $DMG ($(du -h "$DMG" | cut -f1))"
