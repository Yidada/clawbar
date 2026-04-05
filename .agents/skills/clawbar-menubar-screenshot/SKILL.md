---
name: clawbar-menubar-screenshot
description: Capture a desktop screenshot of the Clawbar menu bar popup. Use when working on menu layout, visual regressions, width issues, or when you need to automatically open the Clawbar status item and save a screenshot artifact for review.
---

# Clawbar Menubar Screenshot

Use this skill when you need a reproducible screenshot of the live `Clawbar` menu bar popup.

## Workflow

1. Work from the repository root of the current `clawbar` checkout.
2. Run `./.agents/skills/clawbar-menubar-screenshot/scripts/capture-menubar.sh`.
3. Read the printed output path and inspect the image artifact.

## Behavior

- Builds `Clawbar` by default before capturing.
- Restarts `Clawbar` into a clean single-instance state by default before capturing.
- Uses `python3 Tests/Harness/clawbarctl.py app start --mode ui ...` to make app startup, state injection, and logs consistent with the rest of the repo.
- Opens the menu bar item via macOS Accessibility APIs.
- Saves a full-screen screenshot artifact.

## Output

- Default output path: `Artifacts/MenubarScreenshots/clawbar-menubar-<timestamp>.png`
- You may pass an explicit output path as the first argument.

## Optional Environment

- `CLAWBAR_CAPTURE_BUILD=0` skips `swift build`.
- `CLAWBAR_CAPTURE_RESTART=0` reuses an existing `Clawbar` process instead of restarting it.
- `CLAWBAR_CAPTURE_APP_NAME=<name>` overrides the app process name. Default: `Clawbar`.
- `CLAWBAR_CAPTURE_ITEM_TITLE=<title>` overrides the menu bar item title. Default: `Clawbar`.
- `CLAWBAR_CAPTURE_LAUNCH_WAIT=<seconds>` adjusts post-launch wait time. Default: `2`.
- `CLAWBAR_CAPTURE_OPEN_WAIT=<seconds>` adjusts post-click wait time before capture. Default: `1`.

## Notes

- This workflow requires macOS Accessibility permission so the helper can press the status item.
- The script launches `Clawbar` in a deterministic UI test mode, with a fixed OpenClaw-installed snapshot for repeatable captures.
- Startup logs and tracked app state live under `Artifacts/Harness/Runs/` and `Artifacts/Harness/State/`.
- The script captures the full desktop. Crop or compare the resulting artifact separately if needed.
