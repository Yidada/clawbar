# Changelog

## 0.1.0 — Unreleased

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
