# Burn

macOS menu bar app tracking Claude API usage/cost. Built with SwiftUI + Swift Package Manager.

## Build & Run

- `swift build` — build
- `swift test` — run tests
- After building: `pkill -x Burn; cp .build/debug/Burn Burn.app/Contents/MacOS/Burn && open Burn.app` — always restart the app when changes are ready so the user can see them
