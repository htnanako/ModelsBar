#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PRODUCT_NAME="ModelsBar"
APP_NAME="${PRODUCT_NAME}.app"
VERSION_CONFIG="$ROOT_DIR/Config/Versions.xcconfig"
APP_ICON="$ROOT_DIR/Resources/ModelsBar.icns"
DIST_DIR="$ROOT_DIR/dist"

CONFIGURATION="release"
VERSION=""
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"
BUNDLE_ID="dev.nanako.ModelsBar"
OUTPUT_DIR=""
SIGN_IDENTITY="${APPLE_SIGN_IDENTITY:--}"
SKIP_CODESIGN="${SKIP_CODESIGN:-0}"
IS_CI="${CI:-${GITHUB_ACTIONS:-}}"

usage() {
    echo "usage: ./Scripts/package-app.sh [--configuration debug|release] [--version 1.2.3] [--build-number 42] [--bundle-id id] [--output-dir path]" >&2
}

read_version_value() {
    local key="$1"
    awk -F '=' -v search_key="$key" '
        $1 ~ search_key {
            gsub(/[[:space:]]/, "", $2)
            print $2
            exit
        }
    ' "$VERSION_CONFIG"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration)
            CONFIGURATION="${2:-}"
            shift 2
            ;;
        --version)
            VERSION="${2:-}"
            shift 2
            ;;
        --build-number)
            BUILD_NUMBER="${2:-}"
            shift 2
            ;;
        --bundle-id)
            BUNDLE_ID="${2:-}"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="${2:-}"
            shift 2
            ;;
        --sign-identity)
            SIGN_IDENTITY="${2:-}"
            shift 2
            ;;
        --skip-codesign)
            SKIP_CODESIGN="1"
            shift 1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
    usage
    exit 1
fi

if [[ ! -f "$VERSION_CONFIG" ]]; then
    echo "Missing version config: $VERSION_CONFIG" >&2
    exit 1
fi

if [[ -z "$VERSION" ]]; then
    VERSION="$(read_version_value "MARKETING_VERSION")"
fi

if [[ -z "$VERSION" ]]; then
    echo "Unable to resolve MARKETING_VERSION from $VERSION_CONFIG" >&2
    exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Build number must be numeric for CFBundleVersion: $BUILD_NUMBER" >&2
    exit 1
fi

VERSION="${VERSION#v}"
OUTPUT_DIR="${OUTPUT_DIR:-$DIST_DIR/$CONFIGURATION}"
APP_DIR="$OUTPUT_DIR/$APP_NAME"

echo "Building $PRODUCT_NAME ($CONFIGURATION) version $VERSION ($BUILD_NUMBER)..."
echo "Step 1/4: Build Swift package"
if [[ -n "$IS_CI" ]]; then
    swift build -c "$CONFIGURATION"
else
    swift build -c "$CONFIGURATION" >/dev/null
fi

echo "Step 2/4: Resolve executable output path"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE="$BIN_DIR/$PRODUCT_NAME"
if [[ ! -x "$EXECUTABLE" ]]; then
    echo "Missing executable at $EXECUTABLE" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "Step 3/4: Assemble app bundle"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$PRODUCT_NAME"
cp "$VERSION_CONFIG" "$APP_DIR/Contents/Resources/Versions.xcconfig"
if [[ -f "$APP_ICON" ]]; then
    cp "$APP_ICON" "$APP_DIR/Contents/Resources/ModelsBar.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleIconFile</key>
  <string>ModelsBar</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
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

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

if [[ "$SKIP_CODESIGN" != "1" ]]; then
    echo "Step 4/4: Codesign app bundle"
    codesign --force --deep --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"
else
    echo "Step 4/4: Skip codesign"
fi

echo "Packaged app:"
echo " $APP_DIR"
