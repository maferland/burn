#!/usr/bin/env bash
# Renders every raster asset from the SVG sources. Run it after editing anything in assets/*.svg;
# the PNGs are committed so a normal build and `make app` need no rasterizer at all.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v rsvg-convert &> /dev/null; then
    echo "rsvg-convert is required: brew install librsvg" >&2
    exit 1
fi

render() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }

# The app icon. package_app.sh resizes this one down into the .icns iconset.
render assets/burn-icon.svg 1024 assets/icon.png

# Bare mark, for README badges and anywhere a vector isn't accepted.
mkdir -p assets/exports
for size in 512 256 128 64 32 16; do
    render assets/burn-logo.svg "$size" "assets/exports/burn-logo-${size}.png"
done

# Menu bar glyph. Flat single-tone, loaded as a template image so macOS tints it per menu bar.
render assets/burn-glyph.svg 18 Burn/Resources/MenuBarIcon@1x.png
render assets/burn-glyph.svg 36 Burn/Resources/MenuBarIcon@2x.png
render assets/burn-glyph.svg 500 Burn/Resources/MenuBarIcon.png

# PR tab-strip glyph. Same template-image treatment as the menu bar glyph above.
render assets/pr-icon.svg 18 Burn/Resources/PRIcon@1x.png
render assets/pr-icon.svg 36 Burn/Resources/PRIcon@2x.png

echo "Rendered assets/icon.png, assets/exports/, and the menu bar + PR tab glyphs."
