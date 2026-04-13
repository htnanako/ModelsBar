#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_PATH=""
OUTPUT_PATH=""
VOLUME_NAME="ModelsBar"

usage() {
    echo "usage: ./Scripts/create-dmg.sh --app-path path/to/ModelsBar.app --output-path path/to/ModelsBar.dmg [--volume-name \"ModelsBar 1.2.3\"]" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-path)
            APP_PATH="${2:-}"
            shift 2
            ;;
        --output-path)
            OUTPUT_PATH="${2:-}"
            shift 2
            ;;
        --volume-name)
            VOLUME_NAME="${2:-}"
            shift 2
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

if [[ -z "$APP_PATH" || -z "$OUTPUT_PATH" ]]; then
    usage
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "Missing app bundle: $APP_PATH" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
rm -f "$OUTPUT_PATH"

mkdir -p "$ROOT_DIR/.local"
STAGING_DIR="$(mktemp -d "$ROOT_DIR/.local/dmg-staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_PATH" >/dev/null

echo "Created dmg:"
echo " $OUTPUT_PATH"
