#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"

if [[ ! -f "$WORKFLOW" ]]; then
  echo "Missing release workflow: $WORKFLOW" >&2
  exit 1
fi

required_patterns=(
  "name: Release"
  "flutter build apk --release"
  "flutter build macos --release"
  "flutter build windows --release"
  "flutter build ios --release --no-codesign"
  "SHA256SUMS.txt"
  "gh release create"
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$WORKFLOW"; then
    echo "Release workflow check failed: missing '$pattern'" >&2
    exit 1
  fi
done

echo "Release workflow looks ready."
