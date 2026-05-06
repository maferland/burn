# Burn

macOS menu bar app tracking Claude API usage/cost. Built with SwiftUI + Swift Package Manager.

## Build & Run

- `swift build` — build
- `swift test` — run tests
- After building: `pkill -x Burn; cp .build/debug/Burn Burn.app/Contents/MacOS/Burn && open Burn.app` — always restart the app when changes are ready so the user can see them

## Homebrew tap

There is a `burn` cask in homebrew-core (different app), so the tap-prefixed name is required:

- Install: `brew install maferland/tap/burn`
- Upgrade: `brew upgrade maferland/tap/burn`

Never tell users to run plain `brew upgrade burn` — it resolves to the wrong cask.
