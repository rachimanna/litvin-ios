#!/usr/bin/env bash
set -euo pipefail

# Overlay Litvin files onto a cloned Telegram-iOS tree.
# Must be run FROM INSIDE the tg-ios directory.
# Usage: cd tg-ios && bash /path/to/litvin-ios/scripts/apply_overlay.sh /path/to/litvin-ios

LITVIN_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
TG_ROOT="$(pwd)"

echo "Litvin root: $LITVIN_ROOT"
echo "TG-iOS root: $TG_ROOT"

if [ ! -f "$TG_ROOT/WORKSPACE" ] && [ ! -f "$TG_ROOT/MODULE.bazel" ]; then
  echo "ERROR: current dir does not look like Telegram-iOS root" >&2
  exit 1
fi

# 1. Drop overlay/ onto the tree 1:1
if [ -d "$LITVIN_ROOT/overlay" ]; then
  echo "Copying overlay/ onto Telegram-iOS tree..."
  cp -R "$LITVIN_ROOT/overlay/." "$TG_ROOT/"
fi

# 2. Copy each features/<Module> as a new submodule under submodules/LitvinFeatures/
# Preserves the Sources/ layout so BUILD files can use glob(["Sources/**/*.swift"]).
LITVIN_SUBMOD="$TG_ROOT/submodules/LitvinFeatures"
mkdir -p "$LITVIN_SUBMOD"
for d in "$LITVIN_ROOT"/features/*/; do
  name="$(basename "$d")"
  echo "Overlay feature module: $name"
  rm -rf "$LITVIN_SUBMOD/$name"
  mkdir -p "$LITVIN_SUBMOD/$name"
  if [ -d "$d/Sources" ]; then
    cp -R "$d/Sources" "$LITVIN_SUBMOD/$name/Sources"
  fi
  if [ -f "$d/BUILD" ]; then
    cp "$d/BUILD" "$LITVIN_SUBMOD/$name/BUILD"
  fi
done

# 3. Branding: generate app icons from SVG if ImageMagick/rsvg-convert available
if [ -f "$LITVIN_ROOT/branding/generate_icons.sh" ]; then
  echo "Generating app icons..."
  bash "$LITVIN_ROOT/branding/generate_icons.sh" "$LITVIN_ROOT" "$TG_ROOT"
fi

# 4. String replacements (Telegram → Litvin) across Localizable.strings
if [ -f "$LITVIN_ROOT/scripts/rename_strings.py" ]; then
  python3 "$LITVIN_ROOT/scripts/rename_strings.py" "$LITVIN_ROOT/branding/strings.json" "$TG_ROOT"
fi

echo "Overlay applied."
