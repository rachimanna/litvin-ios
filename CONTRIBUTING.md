# Contributing

## Adding a feature

1. Create `features/<Name>/README.md` — purpose, UX, toggles, integration map (which TG-iOS files to touch and why).
2. Create `features/<Name>/Sources/*.swift` — self-contained module code. Imports are limited to `Foundation`, `UIKit`, `Display`, `SwiftSignalKit`, `Postbox`, `TelegramCore`, `AccountContext`, `TelegramPresentationData`, `ItemListUI`. Do not import `TelegramUI` — keep features independent so a broken TG-iOS refactor does not cascade.
3. Add a toggle field to `LitvinPreferences` in `features/LitvinSettings/Sources/LitvinPreferences.swift`. Set its default in `.default`.
4. Add a settings row in `features/LitvinSettings/Sources/LitvinSettingsController.swift` under the right section.
5. Add a patch file `patches/00NN-feature-<name>.patch` that wires call-site gates in Telegram-iOS to read your predicate. Generate it from a dirty tree:
   ```bash
   cd tg-ios && git diff > ../patches/00NN-feature-<name>.patch && git reset --hard
   ```
6. Append an entry to `features/REGISTRY.md` with exact TG-iOS files patched.
7. Push. CI will build. Download the IPA artifact and sideload.

## Bumping the upstream ref

1. Change `UPSTREAM_REF` at repo root.
2. Re-generate every patch against the new base:
   ```bash
   bash scripts/setup.sh         # clones new ref
   bash scripts/apply_overlay.sh # copies our code in
   # then manually apply each old patch, fix rejects, regenerate
   ```
3. Commit the new `patches/*.patch` and bump `LITVIN_VERSION`.

## Style

- Swift: 4-space indent, no semicolons.
- Comments: only for non-obvious WHY. No block comments at the top of files.
- Localizable strings go through `Litvin.<Section>.<Key>` keys, defined in `overlay/Telegram/Telegram-iOS/en.lproj/Localizable.strings` (append-only).
