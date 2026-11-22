#!/usr/bin/env bash
#
# Builds a distributable Hort release ZIP.
#
#   Scripts/release.sh          # uses repo-root VERSION
#   Scripts/release.sh 1.1.0    # override (must still match the built app)
#
# The app is ad-hoc signed. This does not require an Apple Developer account,
# but macOS will ask users to approve the app on first launch.
#
# Versioning: bump VERSION + CHANGELOG together, merge to main, then run this
# script and `gh release create vX.Y.Z …`. Never ship a ZIP whose Info.plist
# version disagrees with the Git tag.
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Hort"
DIST="dist"
APP="${DIST}/${APP_NAME}.app"

VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
    VERSION="$(tr -d '[:space:]' < VERSION)"
fi

if [ -z "${VERSION}" ]; then
    echo "Could not determine release version." >&2
    exit 1
fi

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "Invalid version '${VERSION}'. Expected a semantic version such as 1.1.0." >&2
    exit 1
fi

FILE_VERSION="$(tr -d '[:space:]' < VERSION)"
if [ "${VERSION}" != "${FILE_VERSION}" ]; then
    echo "Override version ${VERSION} does not match VERSION file (${FILE_VERSION})." >&2
    echo "Bump VERSION (and CHANGELOG) first, or pass the matching version." >&2
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
"Scripts/build-app.sh" release

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

NOTES="${DIST}/release-notes-${VERSION}.md"
# Emit only this version's CHANGELOG section for the GitHub release body.
awk -v ver="${VERSION}" '
  $0 ~ "^## \\[" ver "\\]" { keep=1; print; next }
  keep && $0 ~ /^## \[/ { exit }
  keep { print }
' CHANGELOG.md > "${NOTES}"
if [ ! -s "${NOTES}" ]; then
    echo "No CHANGELOG section found for [${VERSION}]." >&2
    exit 1
fi

echo "Release artifact ready:"
echo "  ${ZIP}"
echo "  ${CHECKSUM}"
echo "  ${NOTES}"
echo
echo "Create the GitHub release with:"
echo "  git tag -a v${VERSION} -m \"Hort ${VERSION}\""
echo "  git push origin v${VERSION}"
echo "  gh release create v${VERSION} ${ZIP} ${CHECKSUM} --title \"Hort ${VERSION}\" --notes-file ${NOTES}"
