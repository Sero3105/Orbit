#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
swift run OrbitCheck
APP=build/Orbit.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Orbit "$APP/Contents/MacOS/Orbit"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Orbit</string>
<key>CFBundleIdentifier</key><string>com.orbit.Orbit</string>
<key>CFBundleName</key><string>Orbit</string>
<key>CFBundleDisplayName</key><string>Orbit</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
# Icon: draw with built binary helper if present, else skip (Finder shows generic)
if [ -f build/AppIcon.icns ]; then cp build/AppIcon.icns "$APP/Contents/Resources/"; fi
codesign --force --deep --sign - "$APP"
echo "Built $APP"
if [ "${INSTALL:-1}" = "1" ]; then
  rm -rf /Applications/Orbit.app
  cp -R "$APP" /Applications/Orbit.app
  echo "Installed /Applications/Orbit.app"
fi
