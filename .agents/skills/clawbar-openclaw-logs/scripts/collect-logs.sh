#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT_DIR/Artifacts/Diagnostics/$STAMP"
SUMMARY="$OUT_DIR/summary.txt"

mkdir -p "$OUT_DIR"

write_section() {
  local title="$1"
  {
    printf '\n== %s ==\n' "$title"
  } >>"$SUMMARY"
}

copy_if_exists() {
  local source="$1"
  local dest_name="$2"

  if [[ -e "$source" ]]; then
    cp -R "$source" "$OUT_DIR/$dest_name"
    printf 'copied: %s -> %s\n' "$source" "$dest_name" >>"$SUMMARY"
  else
    printf 'missing: %s\n' "$source" >>"$SUMMARY"
  fi
}

tail_if_exists() {
  local source="$1"
  local dest_name="$2"
  local lines="${3:-200}"

  if [[ -f "$source" ]]; then
    tail -n "$lines" "$source" >"$OUT_DIR/$dest_name"
    printf 'tailed: %s -> %s (%s lines)\n' "$source" "$dest_name" "$lines" >>"$SUMMARY"
  else
    printf 'missing: %s\n' "$source" >>"$SUMMARY"
  fi
}

{
  printf 'Clawbar + OpenClaw diagnostics\n'
  printf 'generated_at: %s\n' "$(date -Iseconds)"
  printf 'repo_root: %s\n' "$ROOT_DIR"
  printf 'artifact_dir: %s\n' "$OUT_DIR"
} >"$SUMMARY"

write_section "Processes"
ps aux | rg '[C]lawbar|[o]penclaw|[Q]Claw' >"$OUT_DIR/processes.txt" || true
if [[ -s "$OUT_DIR/processes.txt" ]]; then
  printf 'captured: processes.txt\n' >>"$SUMMARY"
else
  printf 'no matching processes found\n' >>"$SUMMARY"
fi

write_section "Repository Artifacts"
tail_if_exists "$ROOT_DIR/Artifacts/DevRunner/clawbar-dev.log" "clawbar-dev.tail.log" 200
tail_if_exists "$ROOT_DIR/Artifacts/SmokeTests/clawbar-smoke.log" "clawbar-smoke.tail.log" 200

write_section "Clawbar User Logs"
tail_if_exists "$HOME/Library/Logs/Clawbar/openclaw-install.log" "openclaw-install.tail.log" 200
tail_if_exists "$HOME/Library/Logs/Clawbar/openclaw-uninstall.log" "openclaw-uninstall.tail.log" 200

write_section "OpenClaw Runtime Logs"
if [[ -d /tmp/openclaw ]]; then
  find /tmp/openclaw -maxdepth 1 -type f | sort >"$OUT_DIR/tmp-openclaw-files.txt"
  latest_runtime_log="$(find /tmp/openclaw -maxdepth 1 -type f | sort | tail -n 1 || true)"
  if [[ -n "${latest_runtime_log:-}" ]]; then
    tail_if_exists "$latest_runtime_log" "openclaw-runtime.tail.log" 300
  else
    printf 'no runtime log files found under /tmp/openclaw\n' >>"$SUMMARY"
  fi
else
  printf 'missing: /tmp/openclaw\n' >>"$SUMMARY"
fi

write_section "OpenClaw Config Logs"
tail_if_exists "$HOME/.openclaw/logs/config-audit.jsonl" "config-audit.tail.jsonl" 200
copy_if_exists "$HOME/.openclaw/logs/config-health.json" "config-health.json"

write_section "macOS Unified Log"
/usr/bin/log show --last 15m --style compact \
  --predicate 'process == "Clawbar" OR eventMessage CONTAINS[c] "openclaw" OR processImagePath CONTAINS[c] "openclaw" OR senderImagePath CONTAINS[c] "openclaw"' \
  >"$OUT_DIR/unified-log.txt" 2>"$OUT_DIR/unified-log.stderr.txt" || true
printf 'captured: unified-log.txt\n' >>"$SUMMARY"

write_section "Optional QClaw Logs"
if [[ -d "$HOME/Library/Logs/QClaw/openclaw" ]]; then
  find "$HOME/Library/Logs/QClaw/openclaw" -maxdepth 1 -type f | sort >"$OUT_DIR/qclaw-log-files.txt"
  latest_qclaw_log="$(find "$HOME/Library/Logs/QClaw/openclaw" -maxdepth 1 -type f | sort | tail -n 1 || true)"
  if [[ -n "${latest_qclaw_log:-}" ]]; then
    tail_if_exists "$latest_qclaw_log" "qclaw-openclaw.tail.log" 200
  fi
else
  printf 'missing: %s\n' "$HOME/Library/Logs/QClaw/openclaw" >>"$SUMMARY"
fi

printf '\nDiagnostics written to %s\n' "$OUT_DIR"
