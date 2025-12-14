# Release process (CurseForge / GitHub)

This repo is set up to support a simple, repeatable release flow using the community-standard **BigWigs Packager**.

## One-time setup

### 1) Create the project on CurseForge
1. Create an addon project on CurseForge.
2. Note the **Project ID** (numeric).

Optional (recommended): add these lines to ChatCopy.toc after you get IDs:
- `## X-Curse-Project-ID: <id>`
- `## X-Wago-ID: <id>` (if you also publish to Wago)
- `## X-WoWI-ID: <id>` (if you also publish to WoWInterface)

### 2) GitHub repository secrets
In GitHub: **Settings → Secrets and variables → Actions**, add:
- `CF_API_KEY` (required for CurseForge uploads)

Optional:
- `WAGO_API_TOKEN` (if you upload to Wago)
- `WOWI_API_TOKEN` (if you upload to WoWInterface)

### 3) Confirm packaging metadata
This repo includes:
- `.pkgmeta` for the packager
- `.github/workflows/release.yml` to build and publish on tag

## Release (recommended: automated)

### Tag + GitHub Release
1. Update the addon version tag you want to release (example: `v1.0.1`).
2. Create and push a Git tag:
   - `git tag v1.0.1`
   - `git push origin v1.0.1`
3. Create a GitHub Release for that tag (or let GitHub Actions do the upload step).

When the workflow runs, it will:
- Build a zip with the correct folder layout
- Replace `@project-version@` in your TOC (if used)
- Upload the zip to CurseForge (and optionally Wago/WoWI if tokens are present)

## Release (manual fallback)
If you don’t want CI yet:
1. Zip the `ChatCopy/` folder so the zip contains:
   - `ChatCopy/ChatCopy.toc`
   - `ChatCopy/ChatCopy.lua`
2. Upload the zip to CurseForge.

## Notes
- Keep tags in the format `vX.Y.Z`.
- If you change the WoW interface version, update `## Interface:` in ChatCopy.toc.
