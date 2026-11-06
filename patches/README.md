# Patches

Unified-diff patches applied by `scripts/apply_patches.sh` after `apply_overlay.sh`. Each patch targets Telegram-iOS at the ref in `UPSTREAM_REF`.

## Generating a patch

```bash
# after overlay, inside tg-ios:
git diff > ../patches/00NN-short-name.patch
```

## Numbering

- `0001-branding-name.patch` — app name, bundle id, URL scheme, `Info.plist` values.
- `0002-branding-chat-list-title.patch` — swap `ChatListController` title to `ChatListBrandedTitle.image()`.
- `0003-branding-login-splash.patch` — swap `AuthorizationSequenceSplashController` art for our splash.
- `0004-settings-litvin-row.patch` — inject the "Litvin" row at top of settings.
- `0005-feature-ghost-mode.patch` — gate read receipts, typing, online.
- `0006-feature-save-deleted.patch` — hook delete + edit pipeline.
- `0007-feature-edit-history-ui.patch` — long-press menu + diff view.
- `0008-feature-anti-ads.patch` — strip sponsored messages.
- `0009-feature-screenshot-bypass.patch` — gate screen-capture blockers.
- `0010-feature-forward-bypass.patch` — gate canCopy/canForward + recompose path.
- `0011-feature-infinite-self-destruct.patch` — remove countdown + silence viewed receipt.
- `0012-feature-forward-scrub.patch` — pre-send metadata cleaner.
- `0013-feature-double-bottom.patch` — second PIN locking an account set.
- `0014-feature-chat-vault.patch` — passphrase-locked chats.
- `0015-feature-channel-digest.patch` — new top-level controller.
- `0016-feature-contact-profile.patch` — new peer-info section.
- `0017-feature-proxy-pool.patch` — MTProto proxy rotator.
- `0018-feature-context-export.patch` — export/import controller.
- `0019-feature-local-ai.patch` — llama.cpp XCFramework binding.

Patches are currently empty placeholders — they are generated once Telegram-iOS is cloned and the feature source modules are wired. See `features/REGISTRY.md` for exact file locations to touch.
