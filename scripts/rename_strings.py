#!/usr/bin/env python3
"""
Rewrite Telegram → Litvin strings across Telegram-iOS Localizable.strings files.
Reads replacement map from branding/strings.json.
"""
import json
import os
import sys
from pathlib import Path

def main():
    if len(sys.argv) < 3:
        print("usage: rename_strings.py <strings.json> <tg-ios-root>", file=sys.stderr)
        sys.exit(2)
    strings_json = Path(sys.argv[1])
    tg_root = Path(sys.argv[2])

    cfg = json.loads(strings_json.read_text(encoding="utf-8"))
    pairs = [(r["from"], r["to"]) for r in cfg["replacements"]]
    # longest first to avoid partial overlap
    pairs.sort(key=lambda p: -len(p[0]))

    touched = 0
    for p in tg_root.rglob("Localizable.strings"):
        try:
            text = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            text = p.read_text(encoding="utf-16")
        new = text
        for a, b in pairs:
            new = new.replace(a, b)
        if new != text:
            p.write_text(new, encoding="utf-8")
            touched += 1
    print(f"Rewrote {touched} .strings file(s).")

if __name__ == "__main__":
    main()
