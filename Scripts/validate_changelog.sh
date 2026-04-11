#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?"usage: $0 <version>"}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG_PATH="${CHANGELOG_PATH:-$ROOT_DIR/CHANGELOG.md}"

if [[ ! -f "$CHANGELOG_PATH" ]]; then
  echo "CHANGELOG.md not found at $CHANGELOG_PATH" >&2
  exit 1
fi

FIRST_LINE="$(grep -m1 '^## ' "$CHANGELOG_PATH" | sed 's/^## //')"
if [[ "$FIRST_LINE" != "${VERSION}"* ]]; then
  echo "Top changelog section is '$FIRST_LINE' but expected '${VERSION} — ...'" >&2
  exit 1
fi

if ! grep -q "^## ${VERSION} " "$CHANGELOG_PATH"; then
  echo "No changelog section found for version ${VERSION}" >&2
  exit 1
fi

if grep -q "^## ${VERSION} .*Unreleased" "$CHANGELOG_PATH"; then
  echo "Changelog section for ${VERSION} is still marked Unreleased; finalize it before tagging." >&2
  exit 1
fi

echo "Changelog OK for ${VERSION}"
