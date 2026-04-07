# Main Branch Packaging And Signing Setup

This document defines the safe split between repository-owned release automation and secrets that must stay outside Git.

## What belongs where

Committed to the repository:

- `.github/actions/setup-release-signing/action.yml`
- `.github/workflows/package-signed-dmg.yml`
- `.github/workflows/package-main.yml`
- `.github/workflows/release-app.yml`
- `Scripts/prepare_signing_assets.py`
- This document and the README updates that point to it

Saved inside the repository but ignored by Git:

- `.local/signing/local-notary.env`
- `.local/signing/notary/AuthKey_<KEY_ID>.p8`
- `.local/signing/github-environment/release-signing/*`

Never commit:

- `.p12` bundles
- `.p8` private keys
- certificate export passwords
- base64-encoded secret values

The repository now ignores `.local/`, so the project can keep machine-local signing material without risking accidental commits.

## Recommended workflow

Use two GitHub Actions paths:

- `push` to `main`: build, test, sign, notarize, staple, validate, and upload the DMG as a workflow artifact
- `push` of `v*` tags: run the same signing chain and publish the DMG to GitHub Releases

That keeps `main` continuously packageable without turning every merge into a public release.

## One-time local bootstrap

Prepare ignored local files from your downloaded signing bundle:

```bash
python3 Scripts/prepare_signing_assets.py \
  --source-dir /absolute/path/to/signing-bundle \
  --output-dir .local/signing \
  --team-id YOUR_TEAM_ID \
  --signing-identity "Developer ID Application: Your Name (YOUR_TEAM_ID)" \
  --notary-key-id YOUR_KEY_ID \
  --notary-issuer-id YOUR_ISSUER_ID
```

For the current Clawbar setup, use your real local values when running the command, not placeholder values.

This writes:

- `.local/signing/local-notary.env`
- `.local/signing/notary/AuthKey_<KEY_ID>.p8`
- `.local/signing/github-environment/release-signing/APPLE_*`

The generated local env also sets `SIGNING_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"` so local `codesign` only uses the login keychain copy of the Developer ID identity.

## Local validation

After bootstrap:

```bash
source .local/signing/local-notary.env
./Scripts/sign_and_notarize.sh
```

If the local notarization run passes, the same secret set is ready for GitHub Actions.

## GitHub setup

Use a GitHub Environment instead of repository-wide secrets. That narrows the scope of the signing material and keeps both workflows on the same secret source.

In GitHub:

1. Open `Settings > Environments`.
2. Create an environment named `release-signing`.
3. Add these six environment secrets, using the file contents from `.local/signing/github-environment/release-signing/`:
   - `APPLE_DEVELOPER_ID_CERT_BASE64`
   - `APPLE_DEVELOPER_ID_CERT_PASSWORD`
   - `APPLE_TEAM_ID`
   - `APPLE_NOTARY_KEY_ID`
   - `APPLE_NOTARY_ISSUER_ID`
   - `APPLE_NOTARY_API_KEY_BASE64`

For a fully automatic `main` packaging flow, do not add required reviewers to the environment.

## GitHub branch safety

If the intention is “package when a PR lands on `main`”, the safe control point is branch protection, not workflow logic.

Recommended GitHub branch protection settings for `main`:

- Require pull requests before merging
- Require status checks to pass
- Restrict direct pushes if the repository policy allows it

With that in place, every `push` to `main` effectively means a reviewed merge, and `package-main.yml` will only package merged code.

## Resulting automation

After the environment secrets are configured:

- merging to `main` runs `Package Main App`
- pushing a `v*` tag runs `Release App`

Both workflows now call the same reusable packaging workflow, which in turn uses the shared temporary keychain import action and the same notarization script. That keeps the signing implementation in one place.
