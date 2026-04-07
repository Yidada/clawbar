# clawbar

[简体中文](README.zh-CN.md)

Clawbar is a macOS 14+ menu bar app for installing, configuring, and operating a local OpenClaw setup. It keeps the operational entry points in one place: install or remove OpenClaw, manage Gateway, Providers, and Channels, inspect current status, and launch the OpenClaw TUI from the menu bar.

## Install

### GitHub Releases

Download the notarized DMG from [GitHub Releases](https://github.com/Yidada/clawbar/releases).

### Run From Source

From the repository root:

```bash
swift build
swift run Clawbar
```

## Requirements

- macOS 14+
- Swift tools 6.2 or newer
- Xcode with a Swift 6.2 toolchain, or standalone Swift 6.2+

`Package.swift` declares `// swift-tools-version: 6.2`. If your machine only has Swift 6.1.x, `swift build`, `swift run`, and `swift test` will fail.

## What Clawbar Manages

- OpenClaw install and uninstall, with execution logs and status feedback in a dedicated window
- Local Gateway token preparation and Gateway background service management
- Provider configuration, default model selection, and authentication state management through the `openclaw` CLI
- Channel management for Feishu registration and WeChat onboarding flows
- Menu bar status summaries for installation state, executable path, and recent operational status

## Repository Layout

- `Sources/ClawbarKit/` shared lifecycle, menu-state, and other testable app logic
- `Sources/Clawbar/` app entry point, SwiftUI/AppKit integration, and OpenClaw management flows
- `Tests/ClawbarTests/` XCTest coverage for shared logic and grouped integration flows
- `Tests/Harness/` harness entrypoint for the dev loop, smoke runs, integration suites, and diagnostics
- `docs/` current process notes and release documentation
- `.agents/skills/` project-owned skills used by contributors and agents
- `References/openclaw/` pinned upstream OpenClaw snapshot for integration details
- `Artifacts/` generated harness runs, diagnostics bundles, screenshots, and other outputs

## Common Workflows

### Run and inspect the app

```bash
swift run Clawbar
python3 Tests/Harness/clawbarctl.py app start --mode menu-bar --restart
python3 Tests/Harness/clawbarctl.py app status
python3 Tests/Harness/clawbarctl.py app stop
```

### Develop and validate

```bash
python3 Tests/Harness/clawbarctl.py app dev-loop
python3 Tests/Harness/clawbarctl.py test unit --coverage-gate
python3 Tests/Harness/clawbarctl.py test smoke
python3 Tests/Harness/clawbarctl.py test integration --suite all
python3 Tests/Harness/clawbarctl.py test integration --suite provider
python3 Tests/Harness/clawbarctl.py test all
python3 Tests/Harness/clawbarctl.py logs collect
```

The harness writes run summaries to `Artifacts/Harness/Runs/` and tracks the background app process in `Artifacts/Harness/State/app-state.json`.

Top-level `Scripts/dev.sh`, `Scripts/check_coverage.sh`, `Scripts/smoke_test.sh`, and `Scripts/test.sh` remain available as compatibility wrappers, but new docs and automation should prefer `Tests/Harness/clawbarctl.py`.

## Packaging and Release

For unsigned local packaging, use `Scripts/package_app.sh`. The default output is a zip; set `OUTPUT_FORMAT=app`, `dmg`, or `both` when you need a different artifact shape.

```bash
OUTPUT_FORMAT=dmg ./Scripts/package_app.sh
```

For local signing and notarization validation, set `SIGNING_IDENTITY` and the required notary environment variables, then run:

```bash
./Scripts/sign_and_notarize.sh
```

Tagged releases use the GitHub Actions release pipeline. Pushing a `v*` tag runs tests, signs the app, submits it for notarization, staples the result, and publishes the DMG to GitHub Releases.

If you publish from GitLab instead of GitHub, the repository also includes a `.gitlab-ci.yml` template that signs and notarizes a DMG on each default-branch merge, uploads it to the GitLab Package Registry, and exposes a download link through GitLab Releases. See [docs/2026-04-07-gitlab-main-branch-release.md](docs/2026-04-07-gitlab-main-branch-release.md).

If you run CI through ByteDance Codebase CI instead of native GitLab runners, use [.codebase/pipelines/main-notarized-release.yml](.codebase/pipelines/main-notarized-release.yml) together with Codebase CI Variables. See [docs/2026-04-07-codebase-ci-main-release.md](docs/2026-04-07-codebase-ci-main-release.md).

## Docs

- [docs/README.md](docs/README.md) for the document index and maintenance conventions
- [Tests/Harness/README.md](Tests/Harness/README.md) for the local control and test harness
- [docs/2026-04-05-notarized-release-process.md](docs/2026-04-05-notarized-release-process.md) for the release pipeline and required GitHub secrets
- [docs/2026-04-06-local-signing-guide.md](docs/2026-04-06-local-signing-guide.md) for local certificate, signing, and notarization steps
- [docs/2026-04-07-gitlab-main-branch-release.md](docs/2026-04-07-gitlab-main-branch-release.md) for the GitLab main-branch packaging pipeline
- [docs/2026-04-07-codebase-ci-main-release.md](docs/2026-04-07-codebase-ci-main-release.md) for the Codebase CI main-branch packaging pipeline

## OpenClaw Reference Workflow

`References/openclaw` is a vendored OpenClaw snapshot for integration work. Read it before changing behavior that depends on OpenClaw internals, and avoid editing it unless the task is explicitly about syncing the pinned reference snapshot.

## Repository Notes

Project-local skills live under `.agents/skills/` and are managed with `python3 Scripts/project_skills.py`. For repository-specific collaboration rules, see `AGENTS.md`.
