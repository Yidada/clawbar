#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/Scripts/check_coverage.sh"
"$ROOT_DIR/Scripts/smoke_test.sh"

echo "All harness checks passed."
