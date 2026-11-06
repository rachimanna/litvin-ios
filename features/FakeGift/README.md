# FakeGift

Local-only "I sent a gift" animation in your own chat view. Nothing goes over
the network — the recipient sees nothing, no payment, no API call. Purely a
client-side bubble that only you see on your device.

Use case: visual testing, UI demos, personal flex in a chat you keep for
yourself (e.g., Saved Messages). Also safe to open the gift picker and
cancel without worrying that a slip sends anything real.

## UX

- From the attachment panel in any chat, a "Litvin: Fake gift" entry opens
  a local-only picker with a grid of sample gift assets shipped with the
  app (shared LottieTGS files already in TG-iOS, no network).
- Picking one appends a "sent gift" bubble to the LOCAL view of that chat
  (overlay, not persisted to Postbox). Reopening the chat clears it,
  matching the "this never happened" semantics.
- A small "local only" badge on the bubble so you never forget.

## Non-goals

- Never calls `payments.sendStarsForm`, `payments.sendPaymentForm`, or any
  gift-related RPC. The feature path explicitly bypasses the engine.
- Never shows up to the recipient. Nothing is persisted on either side.
- Never fabricates an "incoming gift" from someone else — only your own
  outgoing side gets the local bubble. (Pretending someone else sent you
  a gift could be used to deceive third parties screenshotting the chat,
  so we don't offer that direction.)

## Integration (future wiring)

The module here is sources only; wiring into TG-iOS chat views comes in a
later iteration. Hooks needed:

- `submodules/AttachmentUI/Sources/*` — add a Litvin attachment menu entry.
- `submodules/TelegramUI/Sources/ChatHistoryListNode.swift` — overlay a
  non-Postbox view item at the bottom when `FakeGiftStore.pending(for:)`
  is non-empty.
- Local store under `<account-dir>/litvin.db` — per-chat UUID + asset id,
  cleared when the chat is popped.
