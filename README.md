<div align="center">

<img src=".github/icon.png" width="128" alt="Hort app icon">

# Hort

**A local-first visual memory layer for macOS.**

Capture what you copy and screenshot into a calm, searchable card feed.  
Organise, find and export it later. No accounts, no cloud, no telemetry.

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black?logo=apple)](#build--run)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Built with Swift](https://img.shields.io/badge/Swift-SwiftUI-fa7343?logo=swift&logoColor=white&style=flat-square)](https://developer.apple.com/swiftui/)
[![Local AI: Ollama](https://img.shields.io/badge/AI-Ollama%20(local)-000000?style=flat-square&logo=ollama&logoColor=white)](https://ollama.com)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/gedankenlust/Hort/pulls)

[**Download the latest App**](https://github.com/gedankenlust/Hort/releases) · [What it does](#what-it-does) · [Local AI](#local-ai-optional-fully-on-device) · [Privacy](#privacy--security) · [Build](#build--run)

</div>

---

<p align="center">
  <img src=".github/main.png" width="850" alt="Hort main window">
</p>

> It is not important to know how something works. It is important to know where it is.

Not a clipboard manager, not a notes app, not an AI assistant. Just a persistent
memory dashboard you can leave open on a second monitor.

### Download & Install

**Just want to use Hort?** Download the latest release **`.zip`** from the
[Releases](https://github.com/gedankenlust/Hort/releases) page, unzip it, and
move **Hort.app** into your **Applications** folder.

**First launch (the app is open-source and unsigned):** macOS refuses to open it
the first time because it is not from an "identified developer". This is
expected. To allow it:

- **macOS 15 (Sequoia) or newer:** double-click Hort, dismiss the warning, then
  open **System Settings → Privacy & Security**, scroll down, and click
  **"Open Anyway"**. Confirm once.
- **Older macOS:** **right-click (or Control-click) Hort.app → "Open"**, then
  click **"Open"** in the dialog.
- **If macOS says the app is "damaged" (Apple Silicon):** clear the quarantine
  flag once in Terminal:
  ```sh
  xattr -dr com.apple.quarantine /Applications/Hort.app
  ```

You only need to do this once per install or update. Hort is not notarized
because it ships without a paid Apple Developer account. Everything still runs
100% locally on your Mac.

**Requirements:** macOS 14 or newer. The AI features are optional and need a
local [Ollama](https://ollama.com) install.

---

### What it does

Hort runs in the background and turns your digital context into **Memory
Objects**, visual cards in a live feed:

- **Capture:** automatically saves clipboard **text**, **URLs** (shown as
  domain + path, with a link icon) and **images**, plus macOS **screenshots**
  from your Desktop. Text cards use the first line as a title. New captures
  briefly glow so you notice them arrive.
- **Organise:** new captures land in the **Inbox**; drag a card onto one of
  your own **Boards** (create your own, give them a colour that shows as a
  stripe on the card) and **Tags**, mark **favourites**, or **archive** what
  you're done with. **All Memories** is the full stream. Switch between a
  **grid** and a compact **list view**. Rename or delete a tag globally from
  the sidebar; junk tags (bare numbers, dates, units) are filtered out
  automatically. Bulk-archive everything older than a week or a month with one
  click.
- **Retrieve:** instant search across content, source app and tags. Keyword
  search (SQLite FTS5) is fused with **semantic search** (local embeddings) so
  you find things by meaning too; filter the feed by board or tag from the
  sidebar, or click a tag chip directly on a card.
- **Undo:** deleting a card (or a whole selection) shows an undo toast for a
  few seconds, or just press ⌘Z.
- **Quick Look:** press Space or double-click a card to preview an image
  natively, or open a captured URL straight in your browser.
- **Menu bar:** a status item with capture on/off, your last 3 captures, Ask
  and Settings, so Hort stays reachable without the main window open. Hideable
  from Settings, along with an optional "launch at login".
- **Export:** package the memories you're viewing into an **Obsidian-friendly
  ZIP**: one markdown file per memory (with frontmatter) plus an `assets/`
  folder with relatively-linked images.

Cards support **multi-select** (⌘-click, ⇧-click for ranges, ⌘A for all shown)
for bulk archive/delete/favourite, or dragging the whole selection onto a
board.

### How it works

1. A background **Capture Engine** polls the clipboard (~2×/second) and watches
   your Desktop for new screenshots.
2. Each capture becomes a **Memory Object** stored in **SQLite** (the source of
   truth). Images are saved as assets and a thumbnail is generated for the card
   preview.
3. The **dashboard** (the main window) renders the live feed. Selecting a card opens
   the **Inspector** on the right with its metadata, content and actions
   (favourite, copy, export to markdown, archive, delete, tags).
4. The **sidebar** navigates between Memory Feed, Capture Hub (unfiled),
   Archive, Boards and Tags. Drag a card onto a board, tag or Archive to file it.

### Local AI (optional, fully on-device)

Hort can use a local [Ollama](https://ollama.com) instance for AI features.
**Off by default, opt-in in Settings, and nothing ever leaves your machine.**

- **Analyse:** generate a short summary and suggested tags for a memory, on
  demand from the Inspector or automatically via **Autopilot**. Screenshots and
  images are described by a vision model instead of relying on OCR text alone.
- **Semantic search:** every memory is embedded locally so search matches by
  meaning, fused with keyword search. Summaries and tags added by analysis flow
  back into the index automatically.
- **Ask your memory:** ask a question (✨ in the feed header or ⌘L) and get a
  streamed, **source-cited** answer drawn only from your own captures.
- **Summarize selected:** select several cards and ask the Inspector to
  synthesize them into one summary.

Everything runs against models on your own machine; retrieved notes are treated
strictly as data, never as instructions.

### Privacy & Security

**Hort is local-first.** This means your data never leaves your computer. There are no accounts, no cloud sync, no tracking, and no telemetry.

*   **You control the data:** Everything is stored in a local SQLite database on your machine.
*   **No "Surveillance":** Hort does not record your screen or log your keystrokes. It only reacts to two specific user actions:
    1.  When you **copy** something to your clipboard (Cmd+C).
    2.  When a **new screenshot file** appears on your Desktop.
*   **Sensitive Data Protection:** Hort automatically ignores content from password managers (like 1Password or Bitwarden) and skips clipboard items marked as "concealed" or "sensitive" by the system.
*   **App Exclusion:** You can define a list of apps that Hort should completely ignore.
*   **AI stays local & opt-in:** All AI features use a local Ollama instance, are off by default, and send nothing to any cloud.
*   **No content in logs:** Captured text, URLs and OCR are never written to the system log (debug builds log lengths only).
*   **Out of backups:** Hort's data folder is excluded from Time Machine / iCloud backups by default.
*   **Transparency:** You can see exactly what was captured in the feed and delete anything at any time.

---

### How Screenshot Capture Works

Screenshots still land on your Desktop. **This is intentional and correct.**

Hort does not replace the macOS screenshot tool. Instead, it "watches" your Desktop folder like a silent assistant.

1.  **You take a screenshot:** You press `Shift+Cmd+4`. macOS creates a file (e.g., `Screenshot 2026-06-11 at 10.00.00.png`) on your Desktop.
2.  **Hort notices the file:** Hort sees that a new file starting with "Screenshot" has appeared.
3.  **Hort creates a "Memory":** It indexes the image, runs OCR (text recognition) so you can search for words inside the image later, and displays it in your dashboard feed.
4.  **The file stays where it is:** The original file remains on your Desktop. Hort doesn't move or delete your files without permission.

**Why it might not have appeared instantly:**
*   **Timing:** Hort waits about 0.4 seconds after the file appears to make sure macOS has finished writing the image to disk.
*   **Permissions:** On the first launch, macOS asks for "Desktop Folder" access. If this was denied, Hort cannot see the files. You can check this in *System Settings > Privacy & Security > Files and Folders*.
*   **Naming:** Hort looks for files that contain the word "Screenshot" or "Bildschirmfoto" (for German systems). It is designed to work out-of-the-box with standard macOS naming conventions.

---

### Where it stores data

Everything lives locally under **`~/Library/Application Support/Hort/`**:

| Path | Contents |
| --- | --- |
| `~/Library/Application Support/Hort/database/hort.sqlite` | SQLite database, the source of truth (memories, FTS5 search index, semantic vector index) |
| `~/Library/Application Support/Hort/assets/` | Full-size captured images |
| `~/Library/Application Support/Hort/thumbnails/` | Generated card thumbnails |
| `~/Library/Application Support/Hort/exports/` | Single-memory markdown exports (from the Inspector) |

ZIP exports are written to wherever you choose in the save dialog. Settings
(capture on/off, privacy toggles, excluded apps) are stored in macOS
**UserDefaults** under the bundle id `dev.hort.app`.

### Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘1 / ⌘2 / ⌘3 / ⌘4 | Inbox / All Memories / Favorites / Archive |
| ⌘A | Select all shown |
| ⌘F | Search |
| ⌘L | Ask your memory |
| ⌘E | Export shown memories |
| ⌘⌫ | Delete selected memories |
| ⌘Z | Undo the last delete |
| Space | Quick Look the selected card |
| ⌘, | Settings |

### Build & run

Requirements: macOS 14+, Swift toolchain (Xcode command line tools).

```sh
# Build a proper .app bundle into dist/
Scripts/build-app.sh

# Build and install to /Applications
Scripts/build-app.sh release install

# Debug build
Scripts/build-app.sh debug

# Run the tests
swift test

# Build a release ZIP for GitHub Releases
Scripts/release.sh
```

### Tech stack

Swift · SwiftUI · SQLite via [GRDB](https://github.com/groue/GRDB.swift) ·
FTS5 full-text search · optional local AI via [Ollama](https://ollama.com)
(embeddings + LLM, hybrid search & RAG) · English + German localization ·
native macOS (no Electron, no web views, no cloud).

### Project layout

```
App/        App entry point
Core/       Models, theme, engines (memory, files, images), vector math, settings
Services/   Capture engine, clipboard & screenshot monitors
AI/         Local AI: Ollama client, autopilot runtime, embedding indexer, RAG engine
Database/   SQLite setup (GRDB)
UI/         SwiftUI views (dashboard feed, sidebar, inspector, settings, ask, cards)
Export/     Markdown + ZIP export
Tests/      XCTest suite
Scripts/    build-app.sh, release.sh
```

---

### License

Hort is released under the [MIT License](LICENSE).

---

*Hort is open source and contributor-friendly. The architecture is meant to
stay readable and extensible.*
