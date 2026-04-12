# Changelog

## 0.0.6 — 2026-04-12

### Bug Fixes
- Fix app launch crash caused by resource bundle placement incompatible with macOS codesign. SPM's `Bundle.module` only checks the app root, but codesign rejects unsealed contents there. Replace with a custom lookup that finds bundles in `Contents/Resources/`.

## 0.0.4 — 2026-04-12

### Bug Fixes
- Fix app failing to launch by copying SPM resource bundles into the app bundle during packaging.

## 0.0.3 — 2026-04-12

### Improvements
- Update app icon with a new blue claw design featuring a transparent background, properly cropped and exported at all required macOS icon sizes.

## 0.0.1 — 2026-04-11

### Highlights
- Add explicit release metadata with `version.env` and changelog-driven release validation.
- Align notarized DMG packaging and GitHub release workflows around deterministic versioned artifacts.
- Keep DMG as the only public release artifact for now, while preparing the repository for future Homebrew cask publication.

### Packaging & Release
- Make `version.env` the single source of truth for release version defaults.
- Add changelog, metadata, release-note extraction, and artifact validation scripts for local and CI preflight checks.
- Update GitHub Actions release flows so `v<version>` tags must match `version.env`, release notes come from `CHANGELOG.md`, and `main-build` stays as the prerelease packaging channel.

### Documentation
- Rewrite the release docs and README to document the version/changelog-driven release contract.
- Record that Homebrew cask publication is planned but not yet wired into this repository.
