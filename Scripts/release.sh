#!/usr/bin/env bash
#
# Builds a distributable Hort release ZIP.
#
#   Scripts/release.sh          # uses VERSION from Scripts/build-app.sh
#   Scripts/release.sh 1.0.1    # override version for the ZIP name
#
# The app is ad-hoc signed. This does not require an Apple Developer account,
# but macOS will ask users to approve the app on first launch.
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Hort"
BUILD_SCRIPT="Scripts/build-app.sh"
DIST="dist"
APP="${DIST}/${APP_NAME}.app"

VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
    VERSION="$(awk -F'"' '/^VERSION=/{print $2; exit}' "${BUILD_SCRIPT}")"
fi

if [ -z "${VERSION}" ]; then
    echo "Could not determine release version." >&2
    exit 1
fi

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "Invalid version '${VERSION}'. Expected a semantic version such as 1.0.1." >&2
    exit 1
fi

ZIP="${DIST}/${APP_NAME}-${VERSION}.zip"
CHECKSUM="${ZIP}.sha256"

if [ "${ALLOW_DIRTY:-0}" != "1" ]; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Working tree has uncommitted changes. Commit or stash them first." >&2
        echo "Set ALLOW_DIRTY=1 only for local test builds." >&2
        exit 1
    fi
fi

"Scripts/check.sh"

echo "==> Building ${APP_NAME} ${VERSION}"
"${BUILD_SCRIPT}" release

echo "==> Verifying ad-hoc signature"
codesign --verify --deep --strict "${APP}"

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
if [ "${BUILT_VERSION}" != "${VERSION}" ]; then
    echo "Built app version ${BUILT_VERSION} does not match release version ${VERSION}." >&2
    exit 1
fi

echo "==> Creating ${ZIP}"
rm -f "${ZIP}"
(cd "${DIST}" && zip -qry "${APP_NAME}-${VERSION}.zip" "${APP_NAME}.app")

echo "==> Checking ZIP contents"
if ! zipinfo -1 "${ZIP}" | awk -v expected="${APP_NAME}.app/Contents/MacOS/${APP_NAME}" '
    $0 == expected { found = 1 }
    END { exit(found ? 0 : 1) }
'; then
    echo "ZIP does not contain the expected app executable." >&2
    exit 1
fi

echo "==> Writing SHA-256 checksum"
(cd "${DIST}" && shasum -a 256 "$(basename "${ZIP}")" > "$(basename "${CHECKSUM}")")

echo "Release artifact ready:"
echo "  ${ZIP}"
echo "  ${CHECKSUM}"
echo
echo "Create the GitHub release with:"
echo "  gh release create v${VERSION} ${ZIP} ${CHECKSUM} --title \"Hort ${VERSION}\" --notes-file CHANGELOG.md"
