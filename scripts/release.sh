#!/bin/bash
# Build a distributable DMG: build/Orbit-<version>.dmg (+ .sha256).
#   VERSION=1.1.0 ./scripts/release.sh
# Optional notarization (removes the Gatekeeper warning; needs an Apple Developer ID):
#   SIGN_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=orbit ./scripts/release.sh
#   (create the profile once: xcrun notarytool store-credentials orbit)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0.0}"
INSTALL=0 VERSION="$VERSION" ./scripts/package.sh
APP=build/Orbit.app
if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$APP"
fi
DMG="build/Orbit-$VERSION.dmg"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Orbit $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
if [ -n "${SIGN_ID:-}" ]; then
  codesign --sign "$SIGN_ID" --timestamp "$DMG"
  [ -n "${NOTARY_PROFILE:-}" ] && xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait && xcrun stapler staple "$DMG"
fi
(cd build && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Built $DMG"
