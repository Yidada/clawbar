# clawbar

[简体中文](README.zh-CN.md)

Clawbar is a macOS 14+ menu bar app for installing, configuring, and operating a local OpenClaw setup. It keeps the operational entry points in one place: install or remove OpenClaw, manage Gateway, Providers, and Channels, and launch the OpenClaw TUI from the menu bar.

## Install

### GitHub Releases

Download the notarized DMG from [GitHub Releases](https://github.com/Yidada/clawbar/releases).

### Run From Source

From the repository root:

```bash
swift run Clawbar
```

## Requirements

- macOS 14+
- Swift tools `6.2` or newer
- Xcode with a Swift 6.2 toolchain, or standalone Swift 6.2+

`Package.swift` currently declares `// swift-tools-version: 6.2`. If your machine only has Swift 6.1.x, `swift build`, `swift run`, and `swift test` will fail.

## First Run

- Launch Clawbar and look for the menu bar icon.
- If OpenClaw is not installed yet, open the install flow from the menu.
- Use the management window to work with Providers, Gateway, and Channels.
- Launch the OpenClaw TUI directly from the menu bar when you need local debugging or pairing flows.

## What Clawbar Manages

- OpenClaw install and uninstall, with execution logs and status feedback in a dedicated window.
- Local Gateway token preparation and Gateway background service management.
- Provider configuration, default model selection, and authentication state management through the `openclaw` CLI.
- Channel management for Feishu registration and WeChat onboarding flows.
- Menu bar status summaries for installation state, executable path, and recent operational status.

## Development

The main developer entrypoint is the unified harness at `Tests/Harness/clawbarctl.py`.

```bash
swift build
python3 Tests/Harness/clawbarctl.py app dev-loop
python3 Tests/Harness/clawbarctl.py test unit --coverage-gate
python3 Tests/Harness/clawbarctl.py test smoke
python3 Tests/Harness/clawbarctl.py test integration --suite all
python3 Tests/Harness/clawbarctl.py test all
```

Top-level `Scripts/*.sh` commands remain available as compatibility wrappers, but new automation and docs should prefer the harness commands above.

For harness details, see [Tests/Harness/README.md](Tests/Harness/README.md).

## Release

Clawbar uses a tag-driven notarized DMG release flow. Pushing a `v*` tag triggers the GitHub Actions pipeline that runs tests, signs the app, submits it for notarization, staples the result, and publishes the DMG to GitHub Releases.

See [docs/2026-04-05-notarized-release-process.md](docs/2026-04-05-notarized-release-process.md) for the release prerequisites and detailed steps.

## Docs

- [docs/README.md](docs/README.md) for project documentation
- [Tests/Harness/README.md](Tests/Harness/README.md) for the local control and test harness
- [docs/2026-04-05-notarized-release-process.md](docs/2026-04-05-notarized-release-process.md) for signing, notarization, and DMG release details

## Repository Notes

`References/openclaw` is the pinned local OpenClaw reference snapshot for integration work. Project-local skills live under `.agents/skills/` and are managed with `python3 Scripts/project_skills.py`.

For repository-specific conventions, see `AGENTS.md`.
