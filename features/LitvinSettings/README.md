# LitvinSettings

Top-level "Litvin" section in Settings with every feature toggle.

## UX

Settings screen → new first section above "Notifications and Sounds":

```
┌─ LITVIN ───────────────────────────┐
│ ◇  Litvin Settings            →   │
└────────────────────────────────────┘
```

Tap opens `LitvinSettingsController` with grouped toggles:
- Privacy & Ghost  (Ghost mode, Scheduled ghost, No typing, No online)
- History          (Save deleted, Edit history, Anti-ads)
- Media            (Screenshot bypass, Forward bypass, Infinite self-destruct, Forward scrub)
- Vault            (Double bottom, Chat vault)
- Discovery        (Channel digest, Contact profile)
- Tools            (Proxy pool, Context export, Local AI)
- About            (version, build, upstream ref, GitHub link)

## Chat-list branded header

Patch `submodules/ChatListUI/Sources/ChatListController.swift` so the title node renders the "Litvin" wordmark (SVG rasterized into UIImage) left-aligned, at 22pt, color `#C8102E`, in place of the current "Chats" / "Telegram" title. Status bar style follows accent on the chat-list root.

## Integration

- Register `litvinSettingsEntry` in `submodules/SettingsUI/Sources/SettingsController.swift` at the top of `settingsEntries()`.
- Route taps to `openLitvinSettings(context:)` defined here.
- All toggles persist in `LitvinPreferences` under Postbox `PreferencesEntry` namespace `litvin.main` (int32 key `0xL1TV`).
