#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build

VERSION_CONFIG="$ROOT_DIR/Config/Versions.xcconfig"
APP_ICON="$ROOT_DIR/Resources/ModelsBar.icns"
MARKETING_VERSION="$(awk -F '=' '/MARKETING_VERSION/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$VERSION_CONFIG")"
CURRENT_PROJECT_VERSION="$(awk -F '=' '/CURRENT_PROJECT_VERSION/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$VERSION_CONFIG")"

APP_DIR="$ROOT_DIR/.build/debug/ModelsBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/debug/ModelsBar" "$MACOS_DIR/ModelsBar"
cp "$VERSION_CONFIG" "$RESOURCES_DIR/Versions.xcconfig"
if [[ -f "$APP_ICON" ]]; then
  cp "$APP_ICON" "$RESOURCES_DIR/ModelsBar.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>ModelsBar</string>
  <key>CFBundleExecutable</key>
  <string>ModelsBar</string>
  <key>CFBundleIdentifier</key>
  <string>dev.nanako.ModelsBar</string>
  <key>CFBundleIconFile</key>
  <string>ModelsBar</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>ModelsBar</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${MARKETING_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${CURRENT_PROJECT_VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

pkill -x ModelsBar >/dev/null 2>&1 || true
open -n "$APP_DIR"

sleep 1
pgrep -fl ModelsBar || true
