---
name: release
description: Use when publishing a new Burn version — bumps version, commits, pushes, builds, signs, notarizes, creates GitHub release, updates Homebrew tap
---

# Release

Publish a new version of Burn. Handles the full flow: commit, push, build, test, sign, notarize, package, GitHub release, Homebrew tap update.

## Prerequisites

The `make release` target wraps `package_app.sh` with `doppler run --`, so Doppler must be configured for the current directory and must have these secrets in the `burn / prd` config:

- `SIGN_IDENTITY` — e.g. `Developer ID Application: Marc-Antoine Ferland (GZFQ9NT5GJ)`
- `APPLE_ID` — Apple developer account email
- `APPLE_TEAM_ID` — `GZFQ9NT5GJ`
- `NOTARIZE_PASSWORD` — app-specific password from appleid.apple.com (format: `xxxx-xxxx-xxxx-xxxx`)

Verify with `doppler secrets` from the repo root. The matching `Developer ID Application` cert must be in the login keychain (`security find-identity -p codesigning -v`).

If any of these are missing, the script falls back to an unsigned build, which macOS Sonoma silently deletes from `/Applications/` on first launch. Don't ship an unsigned release.

## Steps

1. **Determine version** — check current tag with `git describe --tags --abbrev=0`, bump accordingly:
   - Patch (`v1.5.0` → `v1.5.1`): bugfixes only
   - Minor (`v1.5.0` → `v1.6.0`): new features, non-breaking changes
   - Major (`v1.5.0` → `v2.0.0`): breaking changes
   - Ask user if ambiguous

2. **Bump `BurnVersion.current`** in `Burn/BurnApp.swift` to the new version (without the `v` prefix).

3. **Commit & push** — stage changes, commit, push to `origin main`.

4. **Release** — run:
   ```bash
   make release NEXT_VERSION=vX.Y.Z
   ```
   This runs: `swift test` → `doppler run -- ./scripts/package_app.sh` (build, sign, package DMG, submit to Apple notary, staple) → `gh release create` → `update_homebrew_tap.sh`.

   Notarization takes 30–90 seconds. Watch for `status: Accepted` and `The staple and validate action worked!` in the output.

5. **Verify**:
   - `spctl --assess --type execute --verbose=4 /Applications/Burn.app` should print `accepted` and `source=Notarized Developer ID` after a fresh `brew reinstall --cask maferland/tap/burn`.
   - Confirm release URL and Homebrew tap updated.

## Output

Return the GitHub release URL when done.
