#!/usr/bin/env bash
set -euo pipefail

# Apply Litvin anchor-based edits via scripts/litvin_patch.py. Also applies
# any raw .patch files in patches/ for ad-hoc fixes.
# Run from inside tg-ios.
# Usage: cd tg-ios && bash /path/to/litvin-ios/scripts/apply_patches.sh /path/to/litvin-ios

LITVIN_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
TG_ROOT="$(pwd)"

if [ -f "$LITVIN_ROOT/scripts/litvin_patch.py" ]; then
  python3 "$LITVIN_ROOT/scripts/litvin_patch.py" "$TG_ROOT"
fi

python3 "$LITVIN_ROOT/scripts/appearance_patch.py" "$TG_ROOT"

if [ -d "$LITVIN_ROOT/patches" ]; then
  shopt -s nullglob
  for p in "$LITVIN_ROOT/patches"/*.patch; do
    echo "Applying $(basename "$p")..."
    git apply --ignore-whitespace --whitespace=nowarn --recount --verbose "$p" || {
      echo "git apply refused $p — falling back to GNU patch -l..."
      patch -l -p1 --no-backup-if-mismatch -i "$p" || {
        echo "Patch failed: $p" >&2
        exit 1
      }
    }
  done
fi

echo "All Litvin edits applied."
