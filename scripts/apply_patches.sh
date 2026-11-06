#!/usr/bin/env bash
set -euo pipefail

# Apply every .patch in litvin/patches/ in lexical order against the current directory.
# Run from inside tg-ios.
# Usage: cd tg-ios && bash /path/to/litvin-ios/scripts/apply_patches.sh /path/to/litvin-ios

LITVIN_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
PATCH_DIR="$LITVIN_ROOT/patches"

if [ ! -d "$PATCH_DIR" ]; then
  echo "No patches/ directory, skipping."
  exit 0
fi

shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)
if [ ${#patches[@]} -eq 0 ]; then
  echo "No .patch files found, skipping."
  exit 0
fi

for p in "${patches[@]}"; do
  echo "Applying $(basename "$p")..."
  git apply --ignore-whitespace --whitespace=nowarn --recount --verbose "$p" || {
    echo "git apply refused $p — falling back to GNU patch -l (whitespace-lenient)..."
    patch -l -p1 --no-backup-if-mismatch -i "$p" || {
      echo "Patch failed: $p" >&2
      exit 1
    }
  }
done

echo "All patches applied."
