---
name: clawbar-package-dmg
description: Build and package the current `clawbar` checkout into a `.dmg`. Use when the user wants a local macOS installer artifact from this repo, either unsigned for local sharing/testing or signed and notarized for release validation, instead of only running `swift build`.
---

# Clawbar Package DMG

Use this skill when you need a `.dmg` artifact from the current `clawbar` checkout.

## Workflow

1. Work from the repository root of the current `clawbar` checkout.
2. For a local DMG, run `./.agents/skills/clawbar-package-dmg/scripts/build-dmg.sh`.
3. For a signed and notarized DMG, run `CLAWBAR_DMG_NOTARIZE=1 ./.agents/skills/clawbar-package-dmg/scripts/build-dmg.sh`.
4. Read the printed output path and inspect the generated `dist/` artifacts.

## Behavior

- Defaults to `Scripts/package_app.sh` with `OUTPUT_FORMAT=dmg`.
- Reuses the repository packaging flow for the app bundle, embedded Swift runtime, build metadata, and DMG creation.
- When `CLAWBAR_DMG_NOTARIZE=1`, delegates to `Scripts/sign_and_notarize.sh` for signing, notarization, stapling, and verification.

## Output

- Default DMG path: `dist/Clawbar-<version>.dmg`
- Default app bundle path: `dist/Clawbar.app`

## Important Environment

- `APP_VERSION=<version>` overrides the default UTC date version.
- `DMG_BASENAME=<name>` overrides the DMG filename stem.
- `DIST_DIR=<path>` writes artifacts outside `dist/`.
- `BUILD_CONFIG=release|debug` overrides the Swift build configuration.
- `BUILD_ARCHS="arm64"` or `BUILD_ARCHS="arm64 x86_64"` controls the packaged architectures.
- `SIGNING_IDENTITY=...` signs the app and DMG during packaging.
- `CLAWBAR_DMG_NOTARIZE=1` switches to the signed and notarized release flow.
- For notarization, also set `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`, and either `APPLE_NOTARY_API_KEY_PATH` or `APPLE_NOTARY_API_KEY_BASE64`.

## Notes

- Use the default path for local install testing or ad hoc sharing.
- Use the notarized path only when the release signing credentials are available.
- For broader release context, read `docs/2026-04-05-notarized-release-process.md`.
