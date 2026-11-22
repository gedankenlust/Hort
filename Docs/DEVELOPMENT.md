# Development

## Requirements

- macOS 14 or newer to run Hort
- Swift 6.1 toolchain (Xcode 16.3 or newer) to build it — required by
  GRDB 7, though the package itself still compiles in Swift 5 language mode
- Optional: Gitleaks for local secret scanning

## Checks and builds

```sh
Scripts/check.sh
Scripts/build-app.sh debug
Scripts/build-app.sh release
Scripts/build-app.sh release install
```

`Scripts/check.sh` runs the Swift tests and, when Gitleaks is installed, scans
the Git history. GitHub Actions runs both checks for every pull request.

## Versioning

Hort uses semantic versioning (`MAJOR.MINOR.PATCH`). The single source of truth
is the repo-root [`VERSION`](../VERSION) file. It must stay in sync with:

- `CFBundleShortVersionString` / `CFBundleVersion` in the built app
  (`Scripts/build-app.sh` reads `VERSION`)
- The latest `## [X.Y.Z]` section in [`CHANGELOG.md`](../CHANGELOG.md)
- The Git tag `vX.Y.Z` and GitHub Release

Bump rules:

- **PATCH** — bug fixes and internal cleanups with no user-facing feature
- **MINOR** — new capabilities or noticeable UX improvements (backward compatible)
- **MAJOR** — breaking changes to data layout or public behavior

Always bump `VERSION` and `CHANGELOG.md` in the same commit (or PR) that lands
on `main` before tagging a release. Do not invent a ZIP/tag version that
disagrees with `VERSION`.

## Release artifact

```sh
Scripts/release.sh
```

The release script requires a clean working tree, runs checks, builds and
verifies the ad-hoc signature, confirms the app version matches `VERSION`,
creates the ZIP, writes a SHA-256 checksum, and extracts this version's
changelog section under `dist/`.

Then tag and publish (from a clean `main`):

```sh
git tag -a "v$(tr -d '[:space:]' < VERSION)" -m "Hort $(tr -d '[:space:]' < VERSION)"
git push origin "v$(tr -d '[:space:]' < VERSION)"
gh release create "v$(tr -d '[:space:]' < VERSION)" \
  "dist/Hort-$(tr -d '[:space:]' < VERSION).zip" \
  "dist/Hort-$(tr -d '[:space:]' < VERSION).zip.sha256" \
  --title "Hort $(tr -d '[:space:]' < VERSION)" \
  --notes-file "dist/release-notes-$(tr -d '[:space:]' < VERSION).md"
```

Review the changelog and artifacts before creating the tag. Keep personal
captures, local databases, and `dist/` out of Git — only the tagged source and
the uploaded release assets leave this machine.

## Project layout

```text
App/        App entry point
Core/       Models, settings, storage, theme, and memory engine
Services/   Clipboard and screenshot capture
AI/         Ollama, embeddings, analysis, and local RAG
Database/   SQLite setup through GRDB
UI/         SwiftUI views and design system
Export/     Markdown and ZIP export
Tests/      XCTest suite
Scripts/    Checks, builds, and release packaging
```
