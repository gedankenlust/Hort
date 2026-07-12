# Privacy and Data Handling

Hort is designed to work without an account, cloud service, analytics, or
telemetry. Its application data stays on the Mac.

## What Hort observes

- Changes to the macOS clipboard while capture is enabled.
- New screenshot files created on the Desktop while capture is enabled.

Hort does not record the screen continuously and does not log keystrokes.

## Capture protections

Clipboard items marked concealed, transient, or auto-generated are ignored by
default. Hort also skips clipboard activity from its own app and from bundle
identifiers in the excluded-app list. The default list includes common password
managers.

The excluded-app list applies to clipboard activity. Desktop screenshots are
files created by macOS and cannot reliably be attributed to the foreground app;
review and delete sensitive screenshots manually.

## Local AI

AI features are disabled by default. When enabled, Hort communicates with the
Ollama HTTP service at `http://localhost:11434`. Analysis, embeddings, and
question answering use locally installed models. Hort does not contain a cloud
AI fallback.

## Storage

Hort stores its database, captured image copies, thumbnails, and single-memory
exports under `~/Library/Application Support/Hort/`. The folder is marked as
excluded from system backups where macOS honors that setting.

The Privacy tab in Settings shows the path and current size and can reveal the
folder in Finder. "Clear all memories" deletes database records, captured image
copies, thumbnails, and local search vectors. User-created exports are preserved.

## Logs

Release builds do not log captured contents. Debug logging is limited to event
types, lengths, and operational errors. Bug reports must use fabricated content
and remove personal paths and identifiers.
