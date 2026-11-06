#!/usr/bin/env bash
set -euo pipefail

# Overwrite every image in DefaultAppIcon.xcassets/AppIconLLC.appiconset with
# our Litvin mark rasterized at the right pixel size.
# Usage: bash install_icon.sh <litvin-root> <tg-ios-root>

LITVIN_ROOT="$1"
TG_ROOT="$2"
SRC="$LITVIN_ROOT/branding/icon.svg"
ASSET="$TG_ROOT/Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset"

if [ ! -d "$ASSET" ]; then
  echo "install_icon: $ASSET not found; AppIcon not updated" >&2
  exit 0
fi

if [ -f "$LITVIN_ROOT/branding/icon.png" ]; then
  # A raster icon (branding/icon.png, 1024x1024) wins over the SVG.
  SRC="$LITVIN_ROOT/branding/icon.png"
  if command -v sips >/dev/null 2>&1; then
    RENDER() { sips -s format png -z "$2" "$2" "$1" --out "$3" >/dev/null; }
  elif command -v magick >/dev/null 2>&1; then
    RENDER() { magick "$1" -resize "${2}x${2}" "$3"; }
  elif command -v convert >/dev/null 2>&1; then
    RENDER() { convert "$1" -resize "${2}x${2}" "$3"; }
  else
    echo "install_icon: need sips or ImageMagick" >&2
    exit 1
  fi
elif command -v rsvg-convert >/dev/null 2>&1; then
  RENDER() { rsvg-convert -w "$2" -h "$2" "$1" -o "$3"; }
elif command -v magick >/dev/null 2>&1; then
  RENDER() { magick -background none -density 1024 "$1" -resize "${2}x${2}" "$3"; }
elif command -v convert >/dev/null 2>&1; then
  RENDER() { convert -background none -density 1024 "$1" -resize "${2}x${2}" "$3"; }
else
  echo "install_icon: need rsvg-convert or ImageMagick" >&2
  exit 1
fi

# filename:size mapping, from AppIconLLC.appiconset/Contents.json
declare -a MAP=(
  "BlueNotificationIcon@2x.png:40"
  "BlueNotificationIcon@3x.png:60"
  "Simple@58x58.png:58"
  "Simple@87x87.png:87"
  "Simple@80x80.png:80"
  "BlueIcon@2x-1.png:120"
  "BlueIcon@2x.png:120"
  "BlueIcon@3x.png:180"
  "BlueNotificationIcon.png:20"
  "BlueNotificationIcon@2x-1.png:40"
  "Simple@29x29.png:29"
  "Simple@58x58-1.png:58"
  "Simple@40x40-1.png:40"
  "Simple@80x80-1.png:80"
  "BlueIconIpad@2x.png:152"
  "BlueIconLargeIpad@2x.png:167"
  "Simple-iTunesArtwork.png:1024"
)

for entry in "${MAP[@]}"; do
  name="${entry%:*}"
  size="${entry#*:}"
  RENDER "$SRC" "$size" "$ASSET/$name"
done

echo "install_icon: overwrote $ASSET with Litvin mark"
