#!/usr/bin/env bash
set -euo pipefail

# Rasterize icon.svg to every iOS AppIcon size.
# Requires rsvg-convert (brew install librsvg) or ImageMagick as fallback.
# Usage: bash branding/generate_icons.sh [litvin-root] [tg-ios-root]

LITVIN_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
TG_ROOT="${2:-}"
SRC="$LITVIN_ROOT/branding/icon.svg"
OUT_DIR="$LITVIN_ROOT/branding/icons"
mkdir -p "$OUT_DIR"

sizes=(1024 180 167 152 144 120 114 100 87 80 76 72 60 58 57 50 48 40 29 20)

if command -v rsvg-convert >/dev/null 2>&1; then
  RENDER() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }
elif command -v magick >/dev/null 2>&1; then
  RENDER() { magick -background none -density 1024 "$1" -resize "${2}x${2}" "$3"; }
elif command -v convert >/dev/null 2>&1; then
  RENDER() { convert -background none -density 1024 "$1" -resize "${2}x${2}" "$3"; }
else
  echo "Need rsvg-convert or ImageMagick. brew install librsvg (or imagemagick)." >&2
  exit 1
fi

for s in "${sizes[@]}"; do
  RENDER "$SRC" "$s" "$OUT_DIR/icon-${s}.png"
done

echo "Icons generated in $OUT_DIR"

# If TG-iOS root provided, drop them into the AppIcon asset catalog.
if [ -n "$TG_ROOT" ] && [ -d "$TG_ROOT" ]; then
  ASSET_DIR=""
  for cand in \
    "$TG_ROOT/Telegram/Telegram-iOS/Resources/Images.xcassets/AppIconLLC.appiconset" \
    "$TG_ROOT/Telegram/Telegram-iOS/Images.xcassets/AppIconLLC.appiconset" \
    "$TG_ROOT/Telegram/Telegram-iOS/Resources/Images.xcassets/AppIcon.appiconset" \
    "$TG_ROOT/Telegram/Telegram-iOS/Images.xcassets/AppIcon.appiconset"; do
    if [ -d "$cand" ]; then ASSET_DIR="$cand"; break; fi
  done
  if [ -n "$ASSET_DIR" ]; then
    echo "Writing icons into $ASSET_DIR"
    cp "$OUT_DIR"/icon-*.png "$ASSET_DIR/" || true
  else
    echo "WARN: could not find AppIcon asset catalog in TG-iOS tree." >&2
  fi
fi
