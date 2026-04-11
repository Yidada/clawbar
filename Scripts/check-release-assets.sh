#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"

INPUT="${1:-}"
if [[ -z "$INPUT" ]]; then
  source "$ROOT_DIR/version.env"
  VERSION="${MARKETING_VERSION}"
else
  VERSION="${INPUT#v}"
fi

EXPECTED_DMG="$DIST_DIR/Clawbar-${VERSION}.dmg"
if [[ ! -f "$EXPECTED_DMG" ]]; then
  echo "Missing expected release asset: $EXPECTED_DMG" >&2
  exit 1
fi

echo "Release asset OK: $EXPECTED_DMG"
