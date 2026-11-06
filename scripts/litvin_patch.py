#!/usr/bin/env python3
"""
Anchor-based source edits for Telegram-iOS. Each edit inserts a snippet after
a regex anchor, is idempotent, and fails loudly if the anchor is missing.

Usage: python3 litvin_patch.py <tg-ios-root>
"""
import re
import sys
from pathlib import Path

PEERINFO = "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen"


def insert_after(text, pattern, snippet, label):
    if snippet in text:
        return text
    match = re.search(pattern, text, re.MULTILINE)
    if match is None:
        raise SystemExit(f"[litvin_patch] anchor not found ({label}): {pattern!r}")
    return text[:match.end()] + snippet + text[match.end():]


def add_import(text, module, label):
    line = f"import {module}\n"
    if line in text:
        return text
    imports = list(re.finditer(r"^import [^\n]+\n", text, re.MULTILINE))
    if not imports:
        raise SystemExit(f"[litvin_patch] no imports found ({label})")
    pos = imports[-1].end()
    return text[:pos] + line + text[pos:]


def edit(root, rel, fn):
    path = root / rel
    original = path.read_text(encoding="utf-8")
    updated = fn(original, rel)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
        print(f"[litvin_patch] patched {rel}")
    else:
        print(f"[litvin_patch] already patched {rel}")


def patch_build(text, label):
    return insert_after(
        text,
        r"^\s*deps = \[\n",
        '        "//submodules/LitvinFeatures/LitvinSettings:LitvinSettings",\n',
        label,
    )


def patch_section_enum(text, label):
    return insert_after(text, r"^enum PeerInfoSettingsSection \{\n", "    case litvin\n", label)


def patch_settings_items(text, label):
    text = add_import(text, "LitvinSettings", label)
    text = insert_after(text, r"^enum SettingsSection: Int, CaseIterable \{\n", "    case litvin\n", label)
    text = insert_after(
        text,
        r"^    for section in SettingsSection\.allCases \{\n\s*items\[section\] = \[\]\n\s*\}\n",
        "    items[.litvin]!.append(PeerInfoScreenDisclosureItem(id: 0, text: \"Litvin\", icon: PresentationResourcesSettings.proxy, action: {\n"
        "        interaction.openSettings(.litvin)\n"
        "    }))\n",
        label,
    )
    return text


def patch_settings_actions(text, label):
    text = add_import(text, "LitvinSettings", label)
    return insert_after(
        text,
        r"func openSettings\(section: PeerInfoSettingsSection\) \{[\s\S]*?^        switch section \{\n",
        "        case .litvin:\n"
        "            push(litvinSettingsController(context: self.context))\n",
        label,
    )


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: litvin_patch.py <tg-ios-root>")
    root = Path(sys.argv[1])
    edit(root, f"{PEERINFO}/BUILD", patch_build)
    edit(root, f"{PEERINFO}/Sources/PeerInfoScreen.swift", patch_section_enum)
    edit(root, f"{PEERINFO}/Sources/PeerInfoSettingsItems.swift", patch_settings_items)
    edit(root, f"{PEERINFO}/Sources/PeerInfoScreenSettingsActions.swift", patch_settings_actions)


if __name__ == "__main__":
    main()
