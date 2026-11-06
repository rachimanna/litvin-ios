#!/usr/bin/env python3
"""
Replace "Telegram"/"Telegram Messenger" with "Litvin"/… in Localizable.strings
VALUES only — never keys, so Swift string-table accessors (which use the key
names) keep compiling.

A .strings line looks like:
    "Key_Name" = "User-facing text here";

We rewrite the right-hand side quoted string only.
"""
import json
import re
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) < 3:
        print("usage: rename_strings.py <strings.json> <tg-ios-root>", file=sys.stderr)
        sys.exit(2)
    cfg = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    tg_root = Path(sys.argv[2])
    # longer-match-first to avoid partial overlap collapsing "Telegram Messenger"
    pairs = sorted(
        ((r["from"], r["to"]) for r in cfg["replacements"]),
        key=lambda p: -len(p[0]),
    )

    line_re = re.compile(r'^(\s*"[^"\n]*"\s*=\s*")([^"\n]*)(";\s*)$')

    def rewrite_value(match: re.Match) -> str:
        head, value, tail = match.group(1), match.group(2), match.group(3)
        for a, b in pairs:
            value = value.replace(a, b)
        return f"{head}{value}{tail}"

    touched = 0
    for path in tg_root.rglob("*.strings"):
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            try:
                text = path.read_text(encoding="utf-16")
            except Exception:
                continue
        new_text = "\n".join(
            line_re.sub(rewrite_value, line) for line in text.split("\n")
        )
        if new_text != text:
            path.write_text(new_text, encoding="utf-8")
            touched += 1
    print(f"Rewrote values in {touched} .strings file(s).")


if __name__ == "__main__":
    main()
