#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0.0}"
swift run OrbitCheck
if [ "${UNIVERSAL:-0}" = "1" ]; then   # needs full Xcode (CI); CLT-only builds the host arch
  swift build -c release --arch arm64 --arch x86_64; BIN=.build/apple/Products/Release/Orbit
else
  swift build -c release; BIN=.build/release/Orbit
fi
APP=build/Orbit.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Orbit"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Orbit</string>
<key>CFBundleIdentifier</key><string>com.orbit.Orbit</string>
<key>CFBundleName</key><string>Orbit</string>
<key>CFBundleDisplayName</key><string>Orbit</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
# Icon: regenerate from committed asset when available
if [ -f assets/AppIcon-1024.png ]; then
  rm -rf /tmp/OrbitAppIcon.iconset; mkdir -p /tmp/OrbitAppIcon.iconset
  for s in 16 32 64 128 256 512; do
    sips -z $s $s assets/AppIcon-1024.png --out /tmp/OrbitAppIcon.iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) assets/AppIcon-1024.png --out /tmp/OrbitAppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns /tmp/OrbitAppIcon.iconset -o build/AppIcon.icns
fi
if [ -f build/AppIcon.icns ]; then cp build/AppIcon.icns "$APP/Contents/Resources/"; fi
codesign --force --deep --sign - "$APP"
echo "Built $APP"
if [ "${INSTALL:-1}" = "1" ]; then
  rm -rf /Applications/Orbit.app
  cp -R "$APP" /Applications/Orbit.app
  echo "Installed /Applications/Orbit.app"
fi
