# ScreenshotBypass

Allow screenshots and screen recording in chats where the peer has set `noforwards` (Telegram's "Restrict Saving Content" flag) and in secret chats.

## How it works

Telegram-iOS calls `UIScreen.main.capturedDidChangeNotification` and in secret chats toggles `isSecureTextEntry`-style screen-capture blockers through `updateScreenCaptureEvents`. When `noforwards` is set on a peer, the UI additionally calls into the blocker. This feature short-circuits those calls.

## Integration

- `submodules/TelegramUI/Sources/ChatController.swift` — find `updateScreenCaptureEvents` / `setupScreenCaptureProtection`. Gate with `LitvinPreferences.screenshotBypass`.
- `submodules/TelegramUI/Sources/ChatMessageInteractiveMediaNode.swift` — overlay blur on capture detection. Skip when flag is on.
- `submodules/TelegramUI/Sources/SecretMediaPreviewController.swift` — `captureProtection`. Skip when flag is on.

Note: The server is never told whether the client is "allowed" to screenshot. Removing the client-side blur is purely local. The server still sends a `messageService` event for `noforwards` violations only in some 1-1 secret chats; in that case leave the event-send untouched to avoid tripping the other side's UI mismatch. Or, in aggressive mode, drop the service event too — add a second sub-flag later if demand.

## Sources

`Sources/ScreenshotBypass.swift` — single predicate used at the call sites.
