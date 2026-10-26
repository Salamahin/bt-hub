#!/bin/sh
# Builds "BT Hub.app" into build/ and, with --install, copies it to ~/Applications and launches it.
set -eu
cd "$(dirname "$0")/.."

APP="build/BT Hub.app"
# Homebrew builds inside its own sandbox and passes --disable-sandbox here.
swift build -c release ${SWIFT_BUILD_FLAGS:-}
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/BTHub "$APP/Contents/MacOS/BTHub"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
    <key>CFBundleIdentifier</key><string>dev.salamahin.bthub</string>
    <key>CFBundleName</key><string>BT Hub</string>
    <key>CFBundleDisplayName</key><string>BT Hub</string>
    <key>CFBundleExecutable</key><string>BTHub</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.4.0</string>
    <key>CFBundleVersion</key><string>5</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key><string>BT Hub connects and disconnects audio devices on this Mac.</string>
    <key>NSLocalNetworkUsageDescription</key><string>BT Hub finds your other devices on the network to move audio devices between them.</string>
    <key>CFBundleURLTypes</key><array><dict>
        <key>CFBundleURLName</key><string>dev.salamahin.bthub.key</string>
        <key>CFBundleURLSchemes</key><array><string>bthub</string></array>
    </dict></array>
    <key>NSBonjourServices</key><array><string>_bthub._tcp</string></array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "built $(pwd)/$APP"

if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  pkill -x BTHub 2>/dev/null || true
  rm -rf "$HOME/Applications/BT Hub.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/BT Hub.app"
  echo "installed to ~/Applications"
fi
