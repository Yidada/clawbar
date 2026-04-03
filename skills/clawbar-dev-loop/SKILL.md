---
name: clawbar-dev-loop
description: Run the local Clawbar auto-rebuild development loop for this repository. Use when editing `Package.swift`, files under `Sources/`, or tests under `Tests/` and you want Clawbar to rebuild and relaunch automatically after each save instead of manually rerunning `swift build` and reopening the app.
---

# Clawbar Dev Loop

Run the repository's dev loop wrapper from this skill when the user wants a fast edit-build-restart cycle for the local Clawbar app.

## Workflow

1. Work from the repository root at `/Users/benjamin/Workspace/ai-agents/clawbar`.
2. Start the loop with `./skills/clawbar-dev-loop/scripts/run-dev-loop.sh`.
3. Keep the session open while editing. The loop watches `Package.swift`, `Sources/`, and `Tests/`.
4. Stop the loop with `Ctrl+C` when the user is done.

## Behavior

- Rebuild the app after every detected file change.
- Restart `Clawbar` only when the build succeeds.
- Leave the previously running app untouched when the build fails.
- Write runner logs to `Artifacts/DevRunner/clawbar-dev.log`.

## Notes

- This is automatic restart, not runtime hot reload.
- To change the polling interval, prefix the command with `CLAWBAR_DEV_POLL_INTERVAL=<seconds>`.
- If the user reports that the app did not relaunch, inspect `Artifacts/DevRunner/clawbar-dev.log` first.
