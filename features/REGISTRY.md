# Feature Registry

Every feature module lives under `features/<Name>/Sources/` as Swift files and copies into `tg-ios/submodules/LitvinFeatures/<Name>/` by `apply_overlay.sh`. The INTEGRATION section of each feature says which Telegram-iOS files it hooks and where. A unified-diff patch in `patches/` wires the hook.

## Convention per feature folder

```
features/<Name>/
  README.md              # purpose, UX, toggle path, integration map
  Sources/*.swift        # module code (independent, imports only SwiftSignalKit/Postbox/TelegramCore where noted)
  BUILD                  # Bazel build file (optional, auto-generated if missing)
```

## Integration map

| Feature              | Primary TG-iOS files to patch                                                          |
|----------------------|----------------------------------------------------------------------------------------|
| LitvinSettings       | `submodules/SettingsUI/Sources/SettingsController.swift` (inject row)                  |
| GhostMode            | `submodules/TelegramCore/Sources/*/ReadHistory.swift`, `UpdateChatInputState.swift`, `AccountOnlineStatus.swift` |
| SaveDeleted          | `submodules/TelegramCore/Sources/SyncCore/MessageHistoryHoles.swift` deletion hook, `ChatHistoryLocation.swift` |
| EditHistory          | `submodules/TelegramUI/Sources/ChatMessageTextBubbleContentNode.swift` + core edit event |
| ScreenshotBypass     | `submodules/TelegramUI/Sources/ChatController*.swift` (`updateScreenCaptureEvents`), `ChatMessageItem.swift` |
| ForwardBypass        | `submodules/TelegramUI/Sources/ChatMessageForwardInfoNode.swift`, `ChatInterfaceState.swift` action filters, `canForwardMessage` guards |
| InfiniteSelfDestruct | `submodules/TelegramUI/Sources/SecretMediaPreviewController.swift`, `ChatMessageInteractiveMediaNode.swift` self-destruct timer |
| DoubleBottom         | `submodules/PasscodeUI/Sources/PasscodeSetupController.swift`, `AccountContext.swift` account switching |
| AntiAds              | `submodules/TelegramUI/Sources/ChatHistoryListNode.swift` sponsored-message injection |
| GhostSchedule        | Builds on GhostMode: adds a timer + fake typing emitter                                |
| MessageNotes         | `submodules/TelegramUI/Sources/ChatMessageBubbleItemNode.swift` long-press menu + Saved-Messages sync blob |
| ChannelDigest        | New top-level controller; reads channel histories, ranks locally                       |
| ContactProfile       | New view attached to peer-info screen; reads `MessageHistoryView`                      |
| ForwardScrub         | `submodules/TelegramUI/Sources/MediaForwardMessagesController.swift` pre-send hook     |
| ChatVault            | New store on top of Postbox + `LocalAuth` gate                                         |
| ProxyPool            | `submodules/TelegramCore/Sources/Network/*`, `ProxySettings.swift`                     |
| ContextExport        | New controller that reads/writes Postbox + Preferences + themes dirs                   |
| LocalAI              | New submodule linking `llama.cpp` via XCFramework                                      |

## Pin

All integration offsets target Telegram-iOS at the ref in `UPSTREAM_REF` at repo root. When bumping the upstream ref, each `.patch` is re-generated against the new base.
