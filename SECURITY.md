# Security Policy

Hort handles clipboard contents and screenshots, so privacy and careful data
handling are part of its core behavior.

## Supported versions

Security fixes are provided for the newest public release. Please reproduce a
problem with that version before reporting it when possible.

## Reporting a vulnerability

Please use a [private GitHub security advisory](https://github.com/gedankenlust/Hort/security/advisories/new).
Do not open a public issue for a suspected vulnerability.

Include the Hort and macOS versions, a minimal description, and safe steps to
reproduce the problem. Do not attach real clipboard contents, screenshots,
databases, access tokens, home-directory paths, or other personal data. Use
fabricated examples instead.

Reports will be acknowledged as soon as reasonably possible. Confirmed issues
will be investigated privately, fixed on a separate branch, and disclosed after
a corrected release is available.

## Security boundaries

- Hort stores its database and captured image copies under
  `~/Library/Application Support/Hort/`.
- Clipboard items marked concealed, transient, or auto-generated are skipped
  when the corresponding privacy setting is enabled.
- Common password managers are excluded by bundle identifier by default, and
  users can extend that list.
- Screenshot capture watches new files on the Desktop. It is independent of the
  foreground-app exclusion list.
- Optional AI requests are sent only to Ollama on `localhost:11434`.
- Hort has no account system, cloud sync, analytics, or telemetry.

See [Docs/PRIVACY.md](Docs/PRIVACY.md) for the full data-handling description.
