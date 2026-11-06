#!/usr/bin/env bash
set -euo pipefail

# Overlay Litvin files onto a cloned Telegram-iOS tree.
# Run from inside tg-ios.
# Usage: cd tg-ios && bash /path/to/litvin-ios/scripts/apply_overlay.sh /path/to/litvin-ios

LITVIN_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
TG_ROOT="$(pwd)"

echo "Litvin root: $LITVIN_ROOT"
echo "TG-iOS root: $TG_ROOT"

if [ ! -f "$TG_ROOT/WORKSPACE" ] && [ ! -f "$TG_ROOT/MODULE.bazel" ]; then
  echo "ERROR: current dir does not look like Telegram-iOS root" >&2
  exit 1
fi

# 1. Overlay directory (raw file overlay)
if [ -d "$LITVIN_ROOT/overlay" ] && [ "$(ls -A "$LITVIN_ROOT/overlay" 2>/dev/null)" ]; then
  # Only copy files that are overlays, not the config template (which stays in-repo).
  for f in "$LITVIN_ROOT/overlay"/*; do
    base="$(basename "$f")"
    if [ "$base" = "litvin-configuration.json" ]; then continue; fi
    if [ -f "$f" ]; then
      echo "Overlay: $base"
      cp "$f" "$TG_ROOT/$base"
    elif [ -d "$f" ]; then
      echo "Overlay dir: $base"
      cp -R "$f" "$TG_ROOT/"
    fi
  done
fi

# 2. Copy each features/<Module> as a new submodule under submodules/LitvinFeatures/
# Preserves the Sources/ layout so BUILD files can use glob(["Sources/**/*.swift"]).
LITVIN_SUBMOD="$TG_ROOT/submodules/LitvinFeatures"
mkdir -p "$LITVIN_SUBMOD"
for d in "$LITVIN_ROOT"/features/*/; do
  name="$(basename "$d")"
  # Only modules with a BUILD file are compiled; source-only stubs stay out of
  # the Telegram tree (Telegram 13.1+ lints every Swift file there).
  if [ ! -f "$d/BUILD" ]; then
    echo "Skip feature stub without BUILD: $name"
    continue
  fi
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

# 3. Display-name string replacement (Telegram → Litvin) across Localizable.strings VALUES only
if [ -f "$LITVIN_ROOT/scripts/rename_strings.py" ]; then
  python3 "$LITVIN_ROOT/scripts/rename_strings.py" "$LITVIN_ROOT/branding/strings.json" "$TG_ROOT"
fi

# 4. App icon: rasterize our SVG into the AppIcon asset catalog
if [ -f "$LITVIN_ROOT/scripts/install_icon.sh" ]; then
  bash "$LITVIN_ROOT/scripts/install_icon.sh" "$LITVIN_ROOT" "$TG_ROOT"
fi

echo "Overlay applied."
