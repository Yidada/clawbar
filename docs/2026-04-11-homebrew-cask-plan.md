# Homebrew Cask Plan (Deferred)

This repository is now release-structure-ready for a future Homebrew Cask, but Homebrew publication is intentionally not wired yet.

## Current state

- Public release artifact: `Clawbar-<version>.dmg`
- Public release channel: GitHub Releases
- Version source: `version.env`
- Release notes source: `CHANGELOG.md`

That gives a future tap a stable version string, a stable DMG name, and a predictable release URL shape.

## Expected future layout

When Homebrew is added later, prefer a dedicated tap repository such as `Yidada/homebrew-tap` rather than keeping cask files in this main app repository.

Expected first-pass contents:

- `Casks/clawbar.rb`
- optional CI that updates the cask after a successful GitHub Release
- checksum update flow based on the released DMG

## Constraints for the future tap

- Consume the notarized GitHub Release DMG, not a separate packaging path
- Keep GitHub Releases as the source of truth for downloadable binaries
- Avoid introducing a second version source outside `version.env`
- Do not add Sparkle/appcast as part of the Homebrew work; that is a separate product decision

## Status

Homebrew support is planned, but not implemented in this repository as of 2026-04-11.
