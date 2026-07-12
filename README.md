<div align="center">

<img src=".github/icon.png" width="128" alt="Hort app icon">

# Hort

**A local-first visual memory layer for macOS.**

Capture what you copy and screenshot into a calm, searchable card feed.  
No accounts, no cloud, no telemetry.

[![CI](https://github.com/gedankenlust/Hort/actions/workflows/ci.yml/badge.svg)](https://github.com/gedankenlust/Hort/actions/workflows/ci.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black?logo=apple)](#build--test)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![SwiftUI](https://img.shields.io/badge/Swift-SwiftUI-fa7343?logo=swift&logoColor=white)](https://developer.apple.com/swiftui/)

[**Download Hort**](https://github.com/gedankenlust/Hort/releases) ·
[User guide](Docs/USER_GUIDE.md) ·
[Privacy](Docs/PRIVACY.md) ·
[Roadmap](ROADMAP.md)

</div>

---

<p align="center">
  <img src=".github/main.png" width="850" alt="Hort main window">
</p>

> It is not important to know how something works. It is important to know where it is.

Hort is a persistent memory dashboard for copied text, URLs, images, and macOS
screenshots. It stores everything locally and makes the result searchable,
organisable, and portable.

## Download and install

Download the latest `Hort-<version>.zip` from
[Releases](https://github.com/gedankenlust/Hort/releases), unzip it, and move
`Hort.app` into Applications. Hort requires macOS 14 or newer.

Hort is open source, ad-hoc signed, and not notarized because it ships without a
paid Apple Developer account. On macOS 15 or newer, try to open it once and then
use **System Settings > Privacy & Security > Open Anyway**. On older macOS
versions, Control-click the app and choose **Open**.

Detailed installation and permission help is in the
[user guide](Docs/USER_GUIDE.md).

## What it does

- **Capture:** clipboard text, web URLs, copied images, files, and new macOS
  screenshots from the Desktop. OCR makes screenshot text searchable.
- **Organise:** Inbox, favorites, archive, boards, folders, tags, drag and drop,
  multi-select, and bulk actions.
- **Retrieve:** fast SQLite FTS5 keyword search plus optional local semantic
  search through Ollama.
- **Preview and undo:** native Quick Look, direct URL opening, and undo after
  deletion.
- **Export:** Obsidian-friendly ZIPs with Markdown frontmatter and portable
  image links.
- **Stay available:** an optional menu bar item, launch at login, and English
  and German interfaces.

## Local AI

Optional AI features use an Ollama service on `localhost:11434` and are disabled
by default. Hort has no cloud fallback.

- Generate summaries and suggested tags on demand or through Autopilot.
- Build local embeddings for semantic search.
- Ask questions across selected memories with source citations.
- Analyse images with a locally installed vision model.

Captured text is treated as untrusted data rather than model instructions.

## Privacy

Hort has no accounts, cloud sync, analytics, or telemetry. It skips clipboard
items marked concealed or transient, excludes common password managers by
default, never logs captured content in release builds, and keeps its store under
`~/Library/Application Support/Hort/`.

The Privacy tab shows capture, local AI, telemetry, storage, and excluded-app
status. Read [Privacy and Data Handling](Docs/PRIVACY.md) for exact boundaries,
including how Desktop screenshots differ from clipboard exclusions.

Security problems should be reported privately according to
[SECURITY.md](SECURITY.md), never through a public issue.

## Build and test

Requirements: macOS 14 or newer and Xcode command line tools.

```sh
# Tests plus a local Gitleaks scan when installed
Scripts/check.sh

# Build a release app into dist/
Scripts/build-app.sh release

# Build and install into /Applications
Scripts/build-app.sh release install

# Create a verified ZIP and SHA-256 checksum
Scripts/release.sh
```

See [Development](Docs/DEVELOPMENT.md) for project layout and release details.
GitHub Actions runs tests and a secret scan for every pull request.

## Technology

Swift · SwiftUI · SQLite via [GRDB](https://github.com/groue/GRDB.swift) ·
FTS5 · local Ollama embeddings and generation · native macOS, with no Electron,
web views, accounts, or cloud service.

## Contributing

Focused bug fixes and improvements are welcome. Read
[CONTRIBUTING.md](CONTRIBUTING.md) before submitting a pull request. Use
fabricated data in tests and reports; never include real captures or personal
paths.

Hort is released under the [MIT License](LICENSE).
