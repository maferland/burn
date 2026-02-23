#!/bin/bash
set -euo pipefail

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    echo "Usage: ./scripts/release.sh v1.0.0"
    exit 1
fi

echo "Releasing Burn $VERSION..."

doppler run -- ./scripts/package_app.sh "$VERSION"

echo ""
echo "Release complete!"
echo ""
echo "Next steps:"
echo "  1. Test the DMG: open Burn-${VERSION}-macos.dmg"
echo "  2. Create GitHub release:"
echo "     git tag $VERSION"
echo "     git push origin $VERSION"
echo "     gh release create $VERSION Burn-${VERSION}-macos.dmg --title \"Burn $VERSION\" --generate-notes"
