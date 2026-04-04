# Repository Guidelines

## Project Structure & Module Organization
`clawbar` is a Swift Package Manager macOS menu bar app. Core logic lives in `Sources/ClawbarKit`, while the app entry point and SwiftUI/AppKit integration live in `Sources/Clawbar`. Tests are in `Tests/ClawbarTests`. Developer scripts are in `Scripts/`, run artifacts are written to `Artifacts/`, and design notes or investigation logs belong in `docs/` using names like `2026-04-03-menubar-ui-investigation.md`. `References/` contains upstream material for comparison, not the main codepath.

## Build, Test, and Development Commands
Use the package root for all commands:

- `swift run Clawbar`: build and launch the menu bar app.
- `swift build`: compile the package without running it.
- `swift test`: run the XCTest suite.
- `./Scripts/dev.sh`: watch `Package.swift`, `Sources/`, and `Tests/`, then rebuild and relaunch automatically. Logs go to `Artifacts/DevRunner/clawbar-dev.log`.
- `./Scripts/check_coverage.sh`: run tests with coverage and fail if any function under `Sources/ClawbarKit` is uncovered.
- `./Scripts/smoke_test.sh`: build, launch the smoke harness, and capture `Artifacts/SmokeTests/hello-world-smoke.png`.
- `./Scripts/test.sh`: run the coverage gate and smoke test together.

## Coding Style & Naming Conventions
Follow the existing Swift style: 4-space indentation, one top-level type per file where practical, `UpperCamelCase` for types, `lowerCamelCase` for properties and methods, and clear scene/view names such as `ApplicationManagementView`. Keep UI code thin in `Sources/Clawbar` and push testable logic into `ClawbarKit`. The package enables Swift strict concurrency features, so prefer `Sendable` types and concurrency-safe APIs when adding shared state.

## Testing Guidelines
Tests use `XCTest`. Name test files after the subject under test, for example `AppConfigurationTests.swift`, and use descriptive methods like `testIsSmokeTestEnabledReturnsTrueWhenFlagIsSet`. Add or update unit tests for logic changes in `ClawbarKit`. For menu or window behavior, also run `./Scripts/smoke_test.sh`; UI changes should keep the smoke harness passing and refresh screenshot evidence when relevant.

## Commit & Pull Request Guidelines
Recent history uses short, imperative commit subjects such as `Add OpenClaw install flow and status to Clawbar menu`. Keep commits focused and descriptive. Pull requests should summarize behavior changes, list validation commands run, link the related issue when applicable, and include screenshots for menu/window UI changes. Avoid mixing reference-material updates in `References/` with app changes unless the PR is explicitly about syncing references.

## Project Skills
Treat project-local `.agents/skills/` as the source of truth for this repository. Do not assume `~/.codex/skills` or `~/.agents/skills` exists on another machine. Register every repo-relevant skill in `.agents/skills/registry.json`, keep project-owned skills in-tree, and vendor any external skill into `.agents/skills/<name>` before relying on it in docs or automation. Use `python3 Scripts/project_skills.py list`, `check`, and `sync` to manage the local skill inventory.
