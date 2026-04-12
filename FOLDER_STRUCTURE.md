# Clawbar Repository Folder Structure

## Overview

Clawbar is a macOS menu bar application for managing local OpenClaw installations. This document describes the organization and purpose of each directory and key files in the repository.

## Directory Structure

### Root Level Files

- **`Package.swift`** - Swift Package Manager configuration defining the project targets and dependencies
  - Declares Swift tools version 6.2 requirement
  - Defines two products: `ClawbarKit` (library) and `Clawbar` (executable)
  - Specifies three targets: ClawbarKit, Clawbar, and ClawbarTests
  
- **`README.md`** - Main project documentation with installation, requirements, and usage instructions
- **`README.zh-CN.md`** - Simplified Chinese version of README
- **`CHANGELOG.md`** - Release version history and notable changes
- **`AGENTS.md`** - Repository-specific collaboration rules for agents and contributors
- **`version.env`** - Source of truth for the release version number
- **`.gitignore`** - Git ignore rules for the repository

---

## Source Code (`Sources/`)

### `Sources/ClawbarKit/`
**Shared, testable application logic**

A reusable Swift library containing core lifecycle and state management logic:

- **`AppConfiguration.swift`** - Application configuration and settings management
- **`AppLifecycle.swift`** - App lifecycle management (startup, shutdown, state transitions)
- **`MenuContentModel.swift`** - Data model for menu bar content and state

This library is consumed by the main Clawbar app and tested independently in ClawbarTests.

### `Sources/Clawbar/`
**Main application entry point and UI**

The executable macOS menu bar application with SwiftUI/AppKit integration:

**Core App Files:**
- **`ClawbarApp.swift`** - SwiftUI app entry point and window management
- **`AppDelegate.swift`** - AppKit delegate handling application lifecycle events
- **`ClawbarDebugOptions.swift`** - Debug configuration and logging options
- **`ClawbarEventLogger.swift`** - Event logging for diagnostics

**UI Views & Themes:**
- **`MenuContentView.swift`** - Main menu bar content and layout
- **`MenuPanelSnapshot.swift`** - Snapshot of current menu panel state
- **`ClawbarMenuBarIcon.swift`** - Menu bar icon rendering and updates
- **`ManagementTheme.swift`** - Theme colors and styling for management windows
- **`MenuBarTheme.swift`** - Theme colors and styling for menu bar UI
- **`ApplicationManagementView.swift`** - UI for OpenClaw installation/removal
- **`ApplicationManagementRouting.swift`** - Navigation routing for app management

**OpenClaw Management:**
- **`OpenClawInstaller.swift`** - Handles OpenClaw installation and uninstallation with status tracking
- **`OpenClawInstallView.swift`** - SwiftUI view for installation progress display
- **`OpenClawHealthSnapshot.swift`** - Snapshot of system health and OpenClaw status
- **`OpenClawTUIManager.swift`** - Manages launching and interaction with OpenClaw TUI

**Gateway Management:**
- **`OpenClawGatewayManager.swift`** - Manages local Gateway service lifecycle
- **`OpenClawGatewayCredentialStore.swift`** - Stores and retrieves Gateway credentials
- **`GatewayManagementView.swift`** - SwiftUI view for Gateway configuration

**Provider Management:**
- **`OpenClawProviderManager.swift`** - Configures providers and default model selection
- **`ProviderManagementView.swift`** - SwiftUI view for provider configuration

**Channel Management:**
- **`OpenClawChannelManager.swift`** - Core channel configuration management
- **`OpenClawChannelsSnapshot.swift`** - Snapshot of current channel states
- **`ChannelsManagementView.swift`** - SwiftUI view for channel management UI
- **`ChannelCommandSupport.swift`** - Command-line support for channel operations
- **`OpenClawFeishuChannelManager.swift`** - Feishu-specific channel management
- **`FeishuRegistrationClient.swift`** - Feishu registration and OAuth flow handling

**Other UI Components:**
- **`SmokeTestView.swift`** - UI for smoke testing functionality
- **`SmokeTestWindowPresenter.swift`** - Presents smoke test results window
- **`QRCodeImageView.swift`** - Displays QR codes for channel registration

**Resources:**
- **`Resources/`** - App-specific resources:
  - `ClawbarLogoMaster.png` - Main app logo image
  - `ClawbarMenuBarTemplate18.png` - Menu bar icon at 18pt resolution
  - `ClawbarMenuBarTemplate36.png` - Menu bar icon at 36pt resolution (Retina)

---

## Tests (`Tests/`)

### `Tests/ClawbarTests/`
**XCTest unit and integration tests**

Contains test coverage for shared logic and grouped integration flows:
- Tests for ClawbarKit shared logic
- Integration tests for OpenClaw workflows
- Provider and channel management tests
- Gateway credential storage tests

### `Tests/Harness/`
**Local control and test harness**

Python-based testing and automation framework:
- **`clawbarctl.py`** - Main harness entrypoint for controlling the app in test scenarios
- Development loop automation (dev-loop)
- Smoke test runner
- Integration test suites
- Log collection and diagnostics
- See `Tests/Harness/README.md` for detailed harness documentation

The harness manages:
- App lifecycle control (start, stop, restart)
- Test execution with coverage reporting
- Artifact generation in `Artifacts/Harness/`
- State tracking in `Artifacts/Harness/State/`

---

## Scripts (`Scripts/`)
**Build, packaging, and automation scripts**

### Build & Packaging:
- **`package_app.sh`** - Packages the app as zip, dmg, or both formats
- **`sign_and_notarize.sh`** - Signs and notarizes the app for distribution
- **`generate_logo_assets.swift`** - Regenerates app and menu bar icons from source artwork
- **`generate_app_icon_from_source.swift`** - Generates app icons from source image
- **`extract_status_bar_icon.swift`** - Extracts status bar icon from source

### Release & Validation:
- **`validate_release_metadata.sh`** - Validates release configuration and metadata
- **`validate_changelog.sh`** - Validates CHANGELOG.md format
- **`extract_release_notes.sh`** - Extracts release notes from CHANGELOG
- **`check-release-assets.sh`** - Verifies release assets are present

### Testing & Development:
- **`dev.sh`** - Development workflow (compatibility wrapper)
- **`test.sh`** - Run tests (compatibility wrapper)
- **`check_coverage.sh`** - Check code coverage (compatibility wrapper)
- **`smoke_test.sh`** - Run smoke tests (compatibility wrapper)

### Configuration:
- **`prepare_signing_assets.py`** - Sets up local signing configuration without committing secrets
- **`project_skills.py`** - Manages project-local skills in `.agents/skills/`

All scripts are designed to be invoked from the repository root.

---

## Resources (`Resources/`)
**Asset files for packaging and distribution**

### `Resources/Release/`
- **`Clawbar.icns`** - App icon in macOS format (ready for distribution)
- **`Clawbar-Info.plist`** - App information property list

### `Resources/icons/`
**Source artwork and icons**

- **`ClawbarAppIconSource.png`** - Source image for app icon (used for generation)
- **`ClawbarMenuBarSource.png`** - Source image for menu bar icon
- **`ClawbarMenuBarGlyphSource.png`** - Menu bar glyph/symbol source
- **`ClawbarMenuBarOutlineReference.png`** - Reference for menu bar icon outline
- **`Clawbar.icns`** - Generated macOS app icon
- **Gemini images** - Design reference images

Generated icons are created from source files using `Scripts/generate_logo_assets.swift`.

---

## Documentation (`docs/`)
**Process notes and release documentation**

- **`README.md`** - Documentation index and maintenance conventions
- **`2026-04-03-testing-strategy.md`** - Testing approach and coverage strategy
- **`2026-04-04-project-skills-reorganization.md`** - Agent skills management
- **`2026-04-05-notarized-release-process.md`** - Release pipeline and required secrets
- **`2026-04-06-local-signing-guide.md`** - Certificate, signing, and notarization procedures
- **`2026-04-07-main-branch-packaging-setup.md`** - GitHub Environment setup and ignored files
- **`2026-04-11-homebrew-cask-plan.md`** - Future Homebrew cask distribution plan

---

## GitHub Configuration (`.github/`)

### `.github/workflows/`
**Continuous Integration and Release Workflows**

- **`swift.yml`** - Swift code building and linting
- **`package-main.yml`** - Packages and uploads artifacts when pushing to main
- **`package-signed-dmg.yml`** - Reusable workflow for signing and notarization
- **`release-app.yml`** - Publishes versioned releases to GitHub Releases

### `.github/actions/`
**Custom GitHub Actions**

Reusable action components for workflows.

---

## Agent Skills (`.agents/`)

### `.agents/skills/`
**Project-owned custom skills for contributors and AI agents**

Organized by skill:

- **`clawbar-dev-loop/`** - Development workflow automation
  - `SKILL.md` - Skill documentation
  - `agents/openai.yaml` - OpenAI agent configuration

- **`clawbar-openclaw-logs/`** - OpenClaw log collection
  - `SKILL.md` - Skill documentation
  - `scripts/collect-logs.sh` - Log collection script

- **`clawbar-menubar-screenshot/`** - Menu bar screenshot capture
  - `SKILL.md` - Skill documentation
  - `scripts/capture-menubar.sh` - Screenshot capture
  - `scripts/verify-menubar.sh` - Verification script
  - `scripts/press_status_item.swift` - UI interaction scripts
  - `agents/openai.yaml` - Agent configuration

- **`clawbar-menubar-verify/`** - Menu bar verification
  - `SKILL.md` - Skill documentation
  - `agents/openai.yaml` - Agent configuration

- **`clawbar-package-dmg/`** - DMG packaging
  - `SKILL.md` - Skill documentation
  - `scripts/build-dmg.sh` - DMG build script

- **`registry.json`** - Registry of available skills

Managed via `Scripts/project_skills.py`. See `AGENTS.md` for collaboration rules.

---

## References (`References/`)

### `References/openclaw/`
**Vendored OpenClaw snapshot**

A pinned upstream OpenClaw snapshot for integration reference and development:
- Used to understand OpenClaw internals and dependencies
- Read before changing behavior dependent on OpenClaw
- Avoid editing unless explicitly syncing the pinned reference
- Helps ensure compatibility between Clawbar and OpenClaw versions

---

## Artifacts (`.local/` and `Artifacts/`)

### `.local/signing/` (git-ignored)
**Local signing configuration**

Created via `Scripts/prepare_signing_assets.py`:
- Certificate files
- Signing identity configuration
- Notary API keys
- Local environment configuration

### `Artifacts/Harness/` (git-ignored)
**Generated test and harness outputs**

Created by the test harness:
- **`Runs/`** - Test run summaries and logs
- **`State/`** - Current app state tracking (e.g., `app-state.json`)
- Diagnostic bundles and screenshots

---

## Key Files Summary

| File | Purpose |
|------|---------|
| `Package.swift` | SPM configuration |
| `version.env` | Release version source of truth |
| `CHANGELOG.md` | Release notes source of truth |
| `AGENTS.md` | Collaboration rules |
| `.gitignore` | Git ignore rules |
| `.agents/skills/registry.json` | Available skills registry |

---

## Development Workflow

1. **Source Code**: Modify `Sources/` for features and fixes
2. **Tests**: Add tests in `Tests/ClawbarTests/`
3. **Scripts**: Use `Scripts/` for automation and releases
4. **Documentation**: Update `docs/` with process notes
5. **Skills**: Manage custom skills in `.agents/skills/` via `Scripts/project_skills.py`
6. **Artifacts**: Review outputs in `Artifacts/Harness/` after harness runs

---

## Build & Release Flow

1. **Local Development**: `swift build && swift run Clawbar`
2. **Testing**: `python3 Tests/Harness/clawbarctl.py test all`
3. **Packaging**: `./Scripts/package_app.sh` or `OUTPUT_FORMAT=dmg ./Scripts/package_app.sh`
4. **Signing**: Configure `.local/signing/` then run `./Scripts/sign_and_notarize.sh`
5. **Release**: Create `v<version>` tag matching `version.env` with finalized `CHANGELOG.md`

See `docs/` for detailed process documentation.
