# SaveDeleted

Keep a local copy of messages that were deleted remotely (by sender or by "delete for everyone"), and every past version of edited messages.

## How it works

Telegram-iOS maintains a Postbox-backed message history. When a delete is received, the row is removed. Hook the delete pipeline to copy the row into `LitvinDeletedStore` before removal. For edits, hook the apply-edit pipeline — before overwriting `message.text`, archive the previous `(text, attributes, timestamp)` tuple into `LitvinEditHistoryStore`.

## UX

- A "Deleted" tab appears in chat info when the store has rows for that peer.
- Long-press an edited message → "Show history" opens a diff list.
- Toggle per chat: "Record for this chat" (default on).

## Integration

- `submodules/TelegramCore/Sources/State/ApplyUpdates.swift` — `applyMessageEdit` branch: emit before/after to our store.
- `submodules/TelegramCore/Sources/State/ApplyUpdates.swift` — delete branch: emit soon-to-be-deleted messages to our store.
- Storage: own SQLite file next to Postbox at `<account-dir>/litvin.db`. Schema:
  - `deleted(message_id BIGINT PK, peer_id BIGINT, ts INT, text TEXT, media_blob BLOB, attributes_blob BLOB)`
  - `edits(message_id BIGINT, version INT, ts INT, text TEXT, attributes_blob BLOB, PRIMARY KEY (message_id, version))`

## Sources

- `Sources/LitvinDeletedStore.swift`
- `Sources/LitvinEditHistoryStore.swift`
