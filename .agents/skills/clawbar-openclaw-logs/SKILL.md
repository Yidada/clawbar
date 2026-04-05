---
name: clawbar-openclaw-logs
description: Collect the current Clawbar and OpenClaw runtime logs needed for troubleshooting. Use when the user reports startup failures, gateway state mismatches, missing services, config drift, install/uninstall problems, or asks where to find the active logs for Clawbar or OpenClaw.
---

# Clawbar OpenClaw Logs

Use this skill before ad hoc debugging when Clawbar or OpenClaw is behaving unexpectedly.

## Workflow

1. Work from the repository root of the current `clawbar` checkout.
2. Run `python3 Tests/Harness/clawbarctl.py logs collect` or `./.agents/skills/clawbar-openclaw-logs/scripts/collect-logs.sh`.
3. Inspect the printed artifact directory and start with `summary.txt`.
4. Use the captured log files to confirm the failure mode before proposing a fix.

## Behavior

- Captures the current process list for `Clawbar`, `openclaw`, and related helpers.
- Copies recent Clawbar development and smoke-test logs from `Artifacts/` when present.
- Copies the current harness app state and recent `Artifacts/Harness/Runs/*/summary.json` files when present.
- Copies Clawbar-managed OpenClaw install and uninstall logs from `~/Library/Logs/Clawbar/`.
- Copies the latest OpenClaw gateway runtime logs from `/tmp/openclaw/`.
- Copies OpenClaw config audit logs from `~/.openclaw/logs/`.
- Captures a recent macOS unified log slice filtered to `Clawbar` and `openclaw`.
- Writes everything into `Artifacts/Harness/Runs/<timestamp>-logs-collect/`.

## Notes

- Run this skill first when the user asks why Gateway is stopped, why OpenClaw did not start, or where the current logs live.
- The script is read-only. It gathers evidence and does not mutate OpenClaw or Clawbar state.
- If a source path is missing, the summary will note that explicitly instead of failing the whole collection.
