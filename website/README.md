# Clawbar Website

This folder contains the standalone Vercel landing site for Clawbar.

## Commands

From `website/`:

```bash
npm install
npm run check
npm run build
npm run dev
```

## Content updates

Release metadata and bilingual copy live in `lib/site-content.ts`.

When a new Clawbar release ships, update:

- `releaseInfo.version`
- `releaseInfo.tag`
- `releaseInfo.downloadUrl`
- `releaseInfo.releaseUrl`

The primary download CTA and footer links are derived from that single config object.

## Deployment

Deploy from this directory with Vercel:

```bash
vercel deploy -y
```

For Git-based deployments, configure the Vercel project to use `website/` as the Root Directory and `main` as the Production Branch.

This site is intentionally separate from the Swift package root so the web stack and the macOS app tooling stay isolated.
