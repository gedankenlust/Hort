# Changelog

All notable changes to Hort are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/), and Hort
versions follow [Semantic Versioning](https://semver.org/). The shipping version
lives in the repo-root `VERSION` file.

## [1.1.0] — 2026-11-22

### Added
- Exact **Find / Delete duplicates** for memories (extras only; keepers retained).
- **Privacy blur** for sensitive chrome, plus stronger clipboard/screenshot
  pause and matching behaviour while capture is paused.
- **Autopilot organize**: local heuristics first, then batched Ollama classify,
  with cancel, cool-down, and a serial `OllamaScheduler` (organize > analyze >
  embed).
- Persistent FTS index, `TagPolicy`, and a `MemoryRepository` facade behind
  `MemoryEngine`.
- Archive-aware keyword search and clearer empty/search states.
- Inspector **Quick Look** action; async inspector image preview.

### Fixed
- Tile selection lag at inbox scale: stop running duplicate detection inside
  `DashboardFeedView` body; avoid republishing `AppState` on every inspector
  text hover; COUNT-only inbox polling for the Ollama indicator.
- Feed grid scroll/selection jank and inspector button hit-testing / Dock reopen.
- Soft-delete undo, board orphaning, asset leaks after undo expiry, and search
  index gaps.
- Runtime strings respecting the rendered locale; MacBook sidebar chrome.

### Changed
- GRDB 6 → 7 (tools-version 6.1, Swift 5 language mode retained).
- Capture, privacy, and AI hardening documented in `PRIVACY.md` / `SECURITY.md`.
- Versioning: single `VERSION` file drives the app bundle and release script.

## [1.0.0] — 2026-07-10

First public release. A local-first visual memory layer for macOS: it quietly
captures what you copy and screenshot, and turns it into a searchable,
organisable card feed — with an optional, fully on-device AI layer.

### Capture
- Clipboard **text**, **URLs** (with type detection) and **images**, plus macOS
  **screenshots** from the Desktop, each saved as a Memory Object with a
  generated thumbnail.
- **OCR** on screenshots so you can search the text inside them.

### Organise
- **Inbox / All / Favorites / Archive**, user-created **Boards** (with folders)
  and automatic **Tags**, all via drag & drop.
- **Multi-select**: ⌘-click to toggle, ⇧-click for ranges, ⌘A to select all
  shown. Bulk move-to-board, favorite/un-favorite, archive/restore and delete
  from the inspector — or drag the whole selection onto a board in the sidebar.
- Duplicate consecutive clipboard captures are skipped, and deleting a memory
  also removes its on-disk image/thumbnail.

### Retrieve
- **Hybrid search**: keyword (SQLite FTS5) fused with **semantic search** (local
  embeddings) via reciprocal rank fusion, so you find things by meaning as well
  as exact words. Sidebar filtering by section, board and tag.

### Local AI (optional, off by default, fully on-device via Ollama)
- **Analyse**: a short summary and suggested tags per memory, on demand or
  automatically via **Autopilot** (throttled to one analysis at a time).
  Grounded and low-temperature so tags stay consistent; trivially short clips
  are skipped to avoid hallucinated tags.
- **Ask your memory**: ask a question (✨ in the feed header or ⌘L) and get a
  streamed, **source-cited** answer drawn only from your own captures.
- Live status in the sidebar; sources are fenced and treated strictly as data
  (prompt-injection mitigation). Degrades gracefully when Ollama is off.

### Export
- **Obsidian-friendly ZIP**: one markdown file per memory (with frontmatter)
  plus an `assets/` folder of relatively-linked images.

### Privacy & Security
- Local-first: no accounts, no cloud, no telemetry. Concealed/transient
  clipboard skipped by default; per-app exclusion list (seeded with password
  managers); global pause switch.
- Captured content is never written to the system log; the data folder is
  excluded from Time Machine / iCloud backups; the on-disk store degrades to
  in-memory rather than crashing on a bad database.

### Polish
- Full UI redesign (system font, graphite palette), a responsive card grid that
  fills the available width, tabbed settings, app icon, keyboard shortcuts
  (⌘1–4, ⌘F, ⌘L, ⌘A, ⌘E, ⌘⌫, ⌘,), a brief cinematic boot sequence, English +
  German localization, and an XCTest suite.
- Trimmed the README to the English public-facing version.
- Made the launch-screen status text match the logo and scan-line width.
- Added a repeatable release packaging script and excluded Finder metadata from app bundles.
