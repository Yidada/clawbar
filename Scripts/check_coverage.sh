#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift test --enable-code-coverage >/dev/null
CODECOV_PATH="$(swift test --show-codecov-path)"
TARGET_ROOT="$ROOT_DIR/Sources/ClawbarKit"

python3 - "$CODECOV_PATH" "$TARGET_ROOT" <<'PY'
import json
import sys
from pathlib import Path

codecov_path = Path(sys.argv[1])
target_root = sys.argv[2]

payload = json.loads(codecov_path.read_text())
functions = payload["data"][0]["functions"]
target_functions = [
    function
    for function in functions
    if any(filename.startswith(target_root) for filename in function["filenames"])
]

if not target_functions:
    print(f"No functions found under {target_root}", file=sys.stderr)
    sys.exit(1)

uncovered = [function for function in target_functions if function["count"] == 0]
covered = len(target_functions) - len(uncovered)

print(f"ClawbarKit function coverage: {covered}/{len(target_functions)}")

if uncovered:
    print("Uncovered functions:", file=sys.stderr)
    for function in uncovered:
        print(f"- {function['name']} [{function['filenames'][0]}]", file=sys.stderr)
    sys.exit(1)
PY
