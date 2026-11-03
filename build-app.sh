#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --arch arm64 --arch x86_64
APP="$PWD/dist/AIUsageMonitor.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/AIUsageMonitor" "$APP/Contents/MacOS/AIUsageMonitor"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>AI Usage Monitor</string>
<key>CFBundleDisplayName</key><string>AI Usage Monitor</string>
<key>CFBundleIdentifier</key><string>dev.local.aiusagemonitor</string>
<key>CFBundleExecutable</key><string>AIUsageMonitor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP" || echo 'Ad-hoc signing failed; bundle created anyway.'
fi
(cd dist && rm -f AIUsageMonitor.zip && ditto -c -k --keepParent AIUsageMonitor.app AIUsageMonitor.zip)
printf '\nCreated: %s\n' "$APP"
printf 'Launch with: open "%s"\n' "$APP"
printf 'Release zip: %s\n' "$PWD/dist/AIUsageMonitor.zip"
