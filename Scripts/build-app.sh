#!/usr/bin/env bash
#
# Builds Hort into a proper macOS .app bundle.
#
#   Scripts/build-app.sh            # release build -> dist/Hort.app
#   Scripts/build-app.sh debug      # debug build instead
#   Scripts/build-app.sh release install   # also copy to /Applications
#
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
DO_INSTALL="${2:-}"

APP_NAME="Hort"
BUNDLE_ID="dev.hort.app"
VERSION="1.0.2"

DIST="dist"
APP="${DIST}/${APP_NAME}.app"

echo "▶ Building (${CONFIG})…"
swift build -c "${CONFIG}"
BIN="$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}"

echo "▶ Assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/${APP_NAME}"

if [ -f "Assets/AppIcon.icns" ]; then
    cp "Assets/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
fi

# Copy all assets (standard SPM structure), skipping Finder metadata.
mkdir -p "${APP}/Contents/Resources/Assets"
rsync -a --exclude ".DS_Store" Assets/ "${APP}/Contents/Resources/Assets/"

# Copy localization resources
cp -R Resources/*.lproj "${APP}/Contents/Resources/" 2>/dev/null || true

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSUIElement</key><false/>
</dict>
</plist>
PLIST

echo "▶ Signing (ad-hoc)…"
codesign --force --deep --sign - "${APP}" >/dev/null

echo "✔ Built ${APP}"

if [ "${DO_INSTALL}" = "install" ]; then
    echo "▶ Installing to /Applications…"
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "${APP}" "/Applications/"
    echo "✔ Installed /Applications/${APP_NAME}.app"
    echo "  Launch: open -a ${APP_NAME}"
else
    echo "  Run:     open ${APP}"
    echo "  Install: Scripts/build-app.sh ${CONFIG} install"
fi
