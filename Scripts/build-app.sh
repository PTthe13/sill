#!/bin/bash
# Builds Sill.app. Pass --debug for a debug build.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
[[ "${1:-}" == "--debug" ]] && CONFIG=debug

swift build -c "$CONFIG" --product sill
BIN=$(swift build -c "$CONFIG" --product sill --show-bin-path)/sill

# Universal binary. `swift build --arch` needs Xcode's xcbuild, which isn't
# installed here, so the Intel slice is cross-compiled and lipo'd in.
if [[ "$CONFIG" == release && "${SILL_UNIVERSAL:-1}" == 1 ]]; then
  if swift build -c release --product sill --scratch-path .build/x86 \
       -Xswiftc -target -Xswiftc x86_64-apple-macosx14.0 \
       -Xcc -target -Xcc x86_64-apple-macosx14.0 >/dev/null 2>&1; then
    lipo -create "$BIN" .build/x86/release/sill -output build/sill-universal
    BIN=build/sill-universal
  else
    echo "warning: Intel slice failed to build; shipping arm64 only" >&2
  fi
fi

APP=build/Sill.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sill"
if [[ "$CONFIG" == release ]]; then
  strip -rSTx "$APP/Contents/MacOS/Sill"      # keeps the bundle small
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
[[ -f Resources/Sill.icns ]] && cp Resources/Sill.icns "$APP/Contents/Resources/Sill.icns"

# Ad-hoc by default: enough to run locally. With SILL_SIGN_IDENTITY set to a
# "Developer ID Application: ..." identity, sign for distribution instead —
# hardened runtime and a secure timestamp, both of which notarisation requires.
if [[ -n "${SILL_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp \
             --sign "$SILL_SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=1 "$APP"
else
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1
fi

echo "built $APP ($(du -sh "$APP" | cut -f1))"
