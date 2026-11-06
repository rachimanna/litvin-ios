# GhostMode

Suppress outgoing read receipts, typing indicators, and online status.

## Toggles
- `ghostMode` — do not send `messages.readHistory` / `channels.readHistory` for incoming messages when active chat is opened.
- `ghostNoTyping` — never send `messages.setTyping`.
- `ghostNoOnline` — never send `account.updateStatus(offline: false)`; stay reported offline.

## Integration

### Read receipts
Patch `submodules/TelegramCore/Sources/ApiUtils/MessageHistoryView.swift` and `submodules/TelegramCore/Sources/State/ApplyUpdates.swift` — gate the call sites of `maxReadIncomingMessageId` update / `applyMaxReadIndexInteractively`. Early-return when `LitvinPreferences.ghostMode` is true for 1-1 chats, groups, and channels respectively.

In `submodules/TelegramUI/Sources/ChatHistoryListNode.swift`, the method that posts `maxVisibleIncomingMessageIndex` — wrap its `sendReadIndex` invocation.

### Typing
`submodules/TelegramCore/Sources/TelegramEngine/Messages/RequestEditMessage.swift` is unrelated; the typing signal is in `submodules/TelegramCore/Sources/State/AccountStateManager.swift` via `activityManager`. Hook the `acquireActivity` path in `PeerInputActivityManager.swift` — do not emit activities when `ghostNoTyping` is on.

### Online
`submodules/TelegramCore/Sources/State/AccountStateManager.swift` emits `account.updateStatus(offline: false)` periodically. Guard the ping with `ghostNoOnline`. Also override `account.setContactSignUpNotification` nothing. The periodic wake comes from `ApplicationSpecificNotice.swift` — not relevant; the relevant place is the request submission in `updateAccountOnlineStatus()`.

## Sources

`Sources/GhostMode.swift` — pure predicate functions read by the patched call sites.
