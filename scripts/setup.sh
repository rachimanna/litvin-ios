#!/usr/bin/env bash
set -euo pipefail

# Clone Telegram-iOS at the pinned ref next to this repo as ./tg-ios
# Usage: bash scripts/setup.sh [ref]

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="${1:-$(cat "$REPO_ROOT/UPSTREAM_REF")}"
TARGET="$REPO_ROOT/tg-ios"

if [ -d "$TARGET/.git" ]; then
  echo "tg-ios already cloned, fetching..."
  git -C "$TARGET" fetch --tags --prune
else
  echo "Cloning Telegram-iOS..."
  git clone --recursive https://github.com/TelegramMessenger/Telegram-iOS.git "$TARGET"
fi

git -C "$TARGET" checkout "$REF"
git -C "$TARGET" submodule update --init --recursive

echo "Telegram-iOS ready at $TARGET (ref: $REF)"
