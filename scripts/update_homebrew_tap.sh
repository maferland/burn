#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: update_homebrew_tap.sh VERSION DMG_PATH}"
DMG_PATH="${2:?Usage: update_homebrew_tap.sh VERSION DMG_PATH}"

if [ ! -f "$DMG_PATH" ]; then
    echo "Error: DMG not found at $DMG_PATH"
    exit 1
fi

SHA=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
# Strip leading v for cask version field
CASK_VERSION="${VERSION#v}"

echo "Updating homebrew tap: version=$CASK_VERSION sha256=$SHA"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

gh repo clone maferland/homebrew-tap "$WORK_DIR" -- --depth 1

# Ensure git push can authenticate (gh clone uses GH_TOKEN but git push doesn't)
if [ -n "${GH_TOKEN:-}" ]; then
    git -C "$WORK_DIR" remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/maferland/homebrew-tap.git"
fi

CASK_FILE="$WORK_DIR/Casks/burn.rb"

# Write full cask file — burn repo is source of truth for cask structure
cat > "$CASK_FILE" << CASK
cask "burn" do
  version "$CASK_VERSION"
  sha256 "$SHA"

  url "https://github.com/maferland/burn/releases/download/v#{version}/Burn-v#{version}-macos.dmg"
  name "Burn"
  desc "Track Claude Code spending from the macOS menu bar"
  homepage "https://github.com/maferland/burn"

  depends_on macos: ">= :sonoma"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Burn.app"

  zap trash: "~/Library/Preferences/com.maferland.burn.plist"
end
CASK

cd "$WORK_DIR"
git add Casks/burn.rb
git commit -m "Update burn to $VERSION"
git push

echo "Homebrew tap updated"
