#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

INPUT="${1:-}"
if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
    echo "Usage: $0 <path-to-png>"
    exit 1
fi

WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

echo "▶ Scaling iconset from $INPUT..."
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
    set -- $spec
    sips -z "$1" "$1" "$INPUT" --out "$ICONSET/icon_$2.png" >/dev/null
done

echo "▶ Packing AppIcon.icns..."
mkdir -p Assets
iconutil -c icns "$ICONSET" -o Assets/AppIcon.icns
rm -rf "$WORK"
echo "✔ Wrote Assets/AppIcon.icns"
