#!/usr/bin/env bash
#
# Assemble a minimal macOS .app bundle around the SwiftPM-built `looped` binary,
# so it launches as a proper foreground GUI app (Dock icon, focus, menu) instead
# of a bare executable. Prints the bundle path on the last line.
#
# Usage: scripts/make-app.sh [debug|release]   (default: debug)
#
set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-debug}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

swift build -c "$config" >&2
bin="$(swift build -c "$config" --show-bin-path)"

app=".build/Looped.app"
macos="$app/Contents/MacOS"
rm -rf "$app"
mkdir -p "$macos"
cp "$bin/looped" "$macos/looped"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>looped</string>
	<key>CFBundleIdentifier</key><string>RK.looped</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>Looped</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>15.6</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$app/Contents/PkgInfo"

echo "$app"
