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
if [ ! -f "$CASK_FILE" ]; then
    echo "Error: $CASK_FILE not found in tap repo"
    exit 1
fi

sed -i '' "s/version \".*\"/version \"$CASK_VERSION\"/" "$CASK_FILE"
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA\"/" "$CASK_FILE"

cd "$WORK_DIR"
git add Casks/burn.rb
git commit -m "Update burn to $VERSION"
git push

echo "Homebrew tap updated"
