# ForwardBypass

Allow "Forward" and "Copy" on messages from chats with `noforwards` / `copyProtected`.

## How it works

The client UI hides the forward/copy actions when `peer.flags.contains(.copyProtectionEnabled)` or `message.flags.contains(.CopyProtected)`. The Telegram server does not enforce forwarding server-side for text; it only refuses `messages.forwardMessages` for `noforwards` peers. For the local user: copy is 100% client-side and always works once the UI exposes it. For true forward to another chat, the client re-composes and re-sends the content (not a server-side forward), so it works too.

## Integration

- `submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift` — the menu builder checks `canCopyMessage` / `canForwardMessage`. Patch those predicates to return `true` when `prefs.forwardBypass` is on.
- `submodules/TelegramUI/Sources/ChatControllerShareController.swift` — `messageIds` filtering. Do not filter out `noforwards` items.
- When the user picks "Forward" on a copy-protected message, route through a RE-COMPOSE path: build a fresh outgoing message with the media/text copied locally (use `EnqueueMessage.message` with `attributes: []`, not `.forward`). Add this path in `features/ForwardBypass/Sources/ForwardRecompose.swift`.

## Sources

- `Sources/ForwardBypass.swift` — predicate.
- `Sources/ForwardRecompose.swift` — builder that turns a protected message into a fresh `EnqueueMessage`.
