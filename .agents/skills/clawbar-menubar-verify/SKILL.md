---
name: clawbar-menubar-verify
description: Verify the live Clawbar menu bar popup through macOS Accessibility APIs. Use when working on menu content, accessibility labels, install-vs-installed states, or when you need a repeatable UI regression check instead of a manual click-through.
---

# Clawbar Menubar Verify

Use this skill when you need a reproducible UI check of the live `Clawbar` menu bar popup.

## Workflow

1. Work from the repository root of the current `clawbar` checkout.
2. Run `./.agents/skills/clawbar-menubar-verify/scripts/verify-menubar.sh`.
3. Inspect the printed menu item titles. A non-zero exit means the menu content drifted from the expected UI test snapshot.

## Behavior

- Builds `Clawbar` by default before verifying.
- Restarts `Clawbar` into a clean single-instance state by default before verifying.
- Uses `python3 Tests/Harness/clawbarctl.py app start --mode ui ...` so UI verification shares the same startup and logging flow as smoke and diagnostics runs.
- Launches `Clawbar` in a deterministic UI test mode.
- Opens the menu bar item via macOS Accessibility APIs.
- Verifies the expected menu titles are present in the live popup.

## Optional Environment

- `CLAWBAR_VERIFY_BUILD=0` skips `swift build`.
- `CLAWBAR_VERIFY_RESTART=0` reuses an existing `Clawbar` process instead of restarting it.
- `CLAWBAR_VERIFY_APP_NAME=<name>` overrides the app process name. Default: `Clawbar`.
- `CLAWBAR_VERIFY_ITEM_TITLE=<title>` overrides the menu bar item title. Default: `Clawbar`.
- `CLAWBAR_VERIFY_OPENCLAW_STATE=installed|missing` switches the deterministic OpenClaw state. Default: `installed`.
- `CLAWBAR_VERIFY_LAUNCH_WAIT=<seconds>` adjusts post-launch wait time. Default: `2`.
- `CLAWBAR_VERIFY_OPEN_WAIT=<seconds>` adjusts post-click wait time before verification. Default: `1`.

## Notes

- This workflow requires macOS Accessibility permission so the helper can press and inspect the status item.
- It is an Accessibility-driven regression check adapted to the current SwiftPM executable app shape.
- Startup logs and tracked app state live under `Artifacts/Harness/Runs/` and `Artifacts/Harness/State/`.
