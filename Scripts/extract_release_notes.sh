#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?"usage: $0 <version>"}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG_PATH="${CHANGELOG_PATH:-$ROOT_DIR/CHANGELOG.md}"

if [[ ! -f "$CHANGELOG_PATH" ]]; then
  echo "CHANGELOG.md not found at $CHANGELOG_PATH" >&2
  exit 1
fi

python3 - "$CHANGELOG_PATH" "$VERSION" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text(encoding="utf-8")
pattern = re.compile(
    rf"^## {re.escape(version)} [^\n]*\n(?P<body>.*?)(?=^## |\Z)",
    re.MULTILINE | re.DOTALL,
)
match = pattern.search(text)
if match is None:
    raise SystemExit(f"No changelog section found for version {version}")

body = match.group("body").strip()
if not body:
    raise SystemExit(f"Changelog section for version {version} has no release notes")

print(body)
PY
