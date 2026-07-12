# Development

## Requirements

- macOS 14 or newer
- Swift 5.10-compatible toolchain (Xcode command line tools)
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

## Release artifact

```sh
Scripts/release.sh
```

The release script requires a clean working tree, runs checks, builds and
verifies the ad-hoc signature, confirms the app version, creates the ZIP, and
writes a matching SHA-256 checksum file under `dist/`.

The release remains a deliberate step. Review the changelog and artifacts before
creating a tag and uploading them to GitHub Releases.

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
