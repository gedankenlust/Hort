#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Running Swift tests"
swift test

if command -v gitleaks >/dev/null 2>&1; then
    echo "==> Scanning Git history for secrets"
    gitleaks git . --redact
else
    echo "==> Gitleaks not installed; skipping local secret scan"
    echo "    CI still performs this check on every pull request."
fi
