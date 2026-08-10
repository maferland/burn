# Burn

macOS menu bar app tracking Claude API usage/cost. Built with SwiftUI + Swift Package Manager.

## Build & Run

- `swift build` — build
- `swift test` — run tests
- After building, always restart the app so the user can see the change:

```bash
pkill -x Burn
cp .build/debug/Burn Burn.app/Contents/MacOS/Burn
doppler run -- bash -c 'codesign --force --sign "$SIGN_IDENTITY" --entitlements Burn.entitlements Burn.app'
open Burn.app
```

Copying the binary invalidates the bundle signature, and macOS SIGKILLs an invalid bundle — exit 137, `Killed: 9`, no output. Signing with the release identity instead of ad-hoc (`--sign -`) also keeps Keychain items readable across rebuilds; an ad-hoc signature changes every build, so each build is a stranger to items the last one wrote.

## Icons

`assets/*.svg` are the sources; every PNG under `assets/` and `Burn/Resources/` is generated. After
editing an SVG run `./scripts/render_icons.sh` (needs `brew install librsvg`) and commit the PNGs, so
a normal build and `make app` never need a rasterizer.

The menu bar glyph is deliberately flat and single-tone: macOS tints template images by their alpha
mask, so the gradient and ember core in the full mark would be thrown away.

## Homebrew tap

There is a `burn` cask in homebrew-core (different app), so the tap-prefixed name is required:

- Install: `brew install maferland/tap/burn`
- Upgrade: `brew upgrade maferland/tap/burn`

Never tell users to run plain `brew upgrade burn` — it resolves to the wrong cask.

## Release

Use the `release` skill, or run directly:

```bash
make release NEXT_VERSION=vX.Y.Z
```

The Makefile wraps `package_app.sh` in `doppler run --`. Doppler holds `SIGN_IDENTITY`, `APPLE_ID`, `APPLE_TEAM_ID`, `NOTARIZE_PASSWORD` in the `macos / prd` config, which this directory is already scoped to (`doppler configure`). Without those, the release ships unsigned and macOS Sonoma silently deletes it on first launch from `/Applications/`. See `.claude/skills/release/SKILL.md` for the full checklist.

Also bump `BurnVersion.current` in `Burn/BurnApp.swift` before tagging.
