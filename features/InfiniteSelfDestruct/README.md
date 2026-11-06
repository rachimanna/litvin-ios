# InfiniteSelfDestruct

View one-time ("view-once") photos/videos without the self-destruct timer counting down, and optionally save them.

## How it works

For secret-chat media with TTL, the client enforces the timer locally via `SecretMediaPreviewController`. For "view-once" photos in cloud chats, the media descriptor carries a TTL flag. Removing the local countdown and the auto-dismiss presents the content indefinitely to the local user. The server is NOT told that the user watched it, so the sender sees "unopened" — but see policy below.

## Policy choices

- **Silent view** (default): never fire the "viewed" service event. Sender never gets the "opened" indicator. Local user sees the media forever. Preserves surprise, best privacy for viewer.
- **Honest view**: fire the viewed event normally, but keep the UI open indefinitely for the viewer. Toggle under `infiniteSelfDestructHonest`.
- **Save**: when viewing, offer "Save to Photos" (writes to `PHPhotoLibrary`). Toggle under `infiniteSelfDestructSave`.

## Integration

- `submodules/TelegramUI/Sources/SecretMediaPreviewController.swift` — find the dismissal timer and the `messages.readMessageContents` call. Guard both.
- `submodules/TelegramUI/Sources/ChatMessageInteractiveMediaNode.swift` — self-destruct timer overlay. Guard the countdown fire.
- `submodules/TelegramCore/Sources/TelegramEngine/Messages/RequestMessageActionCallback.swift` — not relevant here; the relevant one is `markMessageContentAsConsumedInteractively` — call becomes a no-op when the silent policy is on.

## Sources

`Sources/InfiniteSelfDestruct.swift` — policy predicate + save helper.
