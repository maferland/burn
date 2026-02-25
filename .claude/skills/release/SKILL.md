---
name: release
description: Use when publishing a new Burn version — bumps version, commits, pushes, builds, creates GitHub release, updates Homebrew tap
---

# Release

Publish a new version of Burn. Handles the full flow: commit, push, build, test, package, GitHub release, Homebrew tap update.

## Steps

1. **Determine version** — check current tag with `git describe --tags --abbrev=0`, bump accordingly:
   - Patch (`v1.5.0` → `v1.5.1`): bugfixes only
   - Minor (`v1.5.0` → `v1.6.0`): new features, non-breaking changes
   - Major (`v1.5.0` → `v2.0.0`): breaking changes
   - Ask user if ambiguous

2. **Commit & push** — stage changes, commit, push to `origin main`

3. **Release** — run:
   ```bash
   make release NEXT_VERSION=vX.Y.Z
   ```
   This runs: `swift test` → `package_app.sh` → `gh release create` → `update_homebrew_tap.sh`

4. **Verify** — confirm release URL and Homebrew tap updated

## Output

Return the GitHub release URL when done.
