---
name: clawbar-dev-loop
description: Run the local Clawbar edit-build-relaunch loop for this repository. Use when working on `Package.swift`, files under `Sources/`, or tests under `Tests/` and you want Clawbar to rebuild and relaunch automatically after each save instead of manually rerunning the app. Do not use for unrelated repository tasks or when a one-off `swift test` or `swift build` run is enough.
---

# Clawbar Dev Loop

Run the repository's dev loop wrapper from this skill when the user wants a fast edit-build-restart cycle for the local Clawbar app.

## Workflow

1. Work from the repository root of the current `clawbar` checkout.
2. Start the loop with `python3 Tests/Harness/clawbarctl.py app dev-loop`.
3. Keep the session open while editing. The loop watches `Package.swift`, `Sources/`, and `Tests/`.
4. Stop the loop with `Ctrl+C` when the user is done.

## Behavior

- Uses the unified harness under `Tests/Harness/` for build, launch, stop, and polling work.
- Rebuild the app after every detected file change.
- Restart `Clawbar` only when the build succeeds.
- Track the current app process in `Artifacts/Harness/State/app-state.json`.
- Write runner logs and app logs under `Artifacts/Harness/Runs/<timestamp>-app-dev-loop/`.

## Notes

- This is automatic restart, not runtime hot reload.
- To change the polling interval, pass `--poll-interval <seconds>`.
- If the user reports that the app did not relaunch, inspect the latest `Artifacts/Harness/Runs/*-app-dev-loop/` directory first.
