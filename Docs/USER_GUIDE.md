# User Guide

## Installation

Download the latest `Hort-<version>.zip` from
[GitHub Releases](https://github.com/gedankenlust/Hort/releases), unzip it, and
move `Hort.app` to Applications.

Hort is ad-hoc signed and not notarized because it is distributed without a paid
Apple Developer account.

- macOS 15 or newer: try to open Hort once, dismiss the warning, then use
  System Settings > Privacy & Security > Open Anyway.
- Older macOS: Control-click `Hort.app`, choose Open, then confirm.
- If macOS reports that the app is damaged, run:

```sh
xattr -dr com.apple.quarantine /Applications/Hort.app
```

## Permissions

On first use, macOS may ask for access to the Desktop folder so Hort can notice
new screenshot files. If access was denied, review System Settings > Privacy &
Security > Files and Folders.

## Screenshot capture

Hort does not replace the macOS screenshot tool. A screenshot still lands on the
Desktop; Hort waits briefly for the file to finish writing, indexes it, runs
local OCR, and leaves the original file untouched. Standard English and German
macOS screenshot names are recognized.

## Storage and deletion

All application data is under `~/Library/Application Support/Hort/`. Open
Settings > Privacy to inspect the path and size, pause capture, manage excluded
apps, or clear memories. Clearing memories preserves files that you exported.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Command-1 / 2 / 3 / 4 | Inbox / All / Favorites / Archive |
| Command-A | Select all shown |
| Command-F | Search |
| Command-L | Ask your memory |
| Command-E | Export shown memories |
| Command-Delete | Delete selected memories |
| Command-Z | Undo the last delete |
| Space | Quick Look the selected card |
| Command-, | Settings |
