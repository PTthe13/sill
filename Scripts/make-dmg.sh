#!/bin/bash
# Builds Sill.app and wraps it in a compressed disk image.
#
# For distribution, set SILL_SIGN_IDENTITY to a "Developer ID Application: ..."
# identity (or its SHA-1 hash, which is what you need when two of them share a
# name) and SILL_NOTARY_PROFILE to a notarytool keychain profile, created once
# with:
#   xcrun notarytool store-credentials <profile> --apple-id <id> \
#       --team-id <team> --password <app-specific-password>
# With both set this signs the app with the hardened runtime, signs the image,
# submits it, waits, and staples the ticket.
#
# Unnotarised, Gatekeeper blocks the first launch, and since macOS 15 the old
# right-click > Open bypass is gone: the user has to go to System Settings >
# Privacy & Security > Open Anyway.
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
    codesign --force --timestamp --sign "$SILL_SIGN_IDENTITY" "$DMG"
fi

if [[ -n "${SILL_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$SILL_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl -a -vvv -t open --context context:primary-signature "$DMG"
fi

echo "built $DMG ($(du -h "$DMG" | cut -f1))"
