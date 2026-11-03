#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --arch arm64 --arch x86_64
APP="$PWD/dist/Gauge.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Gauge" "$APP/Contents/MacOS/Gauge"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Gauge</string>
<key>CFBundleDisplayName</key><string>Gauge</string>
<key>CFBundleIdentifier</key><string>dev.local.gauge</string>
<key>CFBundleExecutable</key><string>Gauge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.2</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP" || echo 'Ad-hoc signing failed; bundle created anyway.'
fi
(cd dist && rm -f Gauge.zip && ditto -c -k --keepParent Gauge.app Gauge.zip)
printf '\nCreated: %s\n' "$APP"
printf 'Launch with: open "%s"\n' "$APP"
printf 'Release zip: %s\n' "$PWD/dist/Gauge.zip"
