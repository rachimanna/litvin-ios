# Litvin runtime feature map

The active implementation is in LitvinCore, LitvinSettings and overlay/submodules/TelegramCore. The older standalone feature folders are compatibility/reference helpers; copying a folder is not itself integration. scripts/feature_patches.py wires behavior against UPSTREAM_REF and fails if an expected anchor changes.

| Feature | Runtime / integration |
| --- | --- |
| Privacy switches and persistence | LitvinOptions; native Litvin settings |
| Ghost read receipts | SynchronizePeerReadState, MarkAllChatsAsRead, InstallInteractiveReadMessagesAction, forum/reply read paths |
| Ghost typing | ManagedLocalInputActivities |
| Online schedules | ManagedAccountPresence; 30-second timer while the client runs |
| Sponsored messages | AdMessages cached state and activation |
| Screenshots in protected cloud chats | ChatControllerNode; secret/verification protection retained |
| Forward/copy controls | ChatInterfaceStateContextMenus; EnqueueMessage fresh-message conversion |
| Media export scrub | LitvinMediaScrub; image re-render, video re-encode, optional voice pitch shift |
| Viewed-media control | MarkMessageContentAsConsumedInteractively; SecretMediaPreviewController |
| Deleted text and edits | AccountStateManagementUtils; loaded ChatHistoryListNode messages; LitvinArchive |
| Text diff | LitvinTextDiff and per-message version screen |
| Notes, tags, colors, reminders | Message menu and LitvinTools; local UNUserNotificationCenter reminders |
| Digest | Selected locally observed channels; LitvinArchive.digest |
| Contact timeline | Observed messages and explicit presence updates; local counts and response-time median |
| Selected-chat PIN concealment | ChatListNode, search wrappers, direct-chat cover, background lock, notification preview redaction |
| Encrypted Litvin history | LitvinPrivateArchive and LitvinVault; selected text/history/notes only; original Telegram storage is independent |
| Proxy pool | ProxyServersStatuses MTProto checks and updateProxySettingsInteractively |
| Context backup | LitvinContextBackup and LitvinBackup; authenticated export, same-account restore, explicit apply confirmation |
| Local gift demo | Message menu; marked local overlay; no gift/payment request |
| ESign distribution | Manual Publish IPA for ESign action, source/checksum generation and in-app installation help |

No AI module is enabled or added. Local data is partitioned by account. Features that preserve content begin collecting only after opt-in. See README for behavior limits and installation steps.

## Local appearance (0.3.0)

LitvinAppearance stores account-separated Premium styling, a display-only phone value, a display-only Stars balance and per-peer NFT gift selections. Profile/header and My Stars patches read these values only for rendering. Native entitlement, credentials, payment balances and gift mutation RPCs are unchanged. NFT entries use original getUniqueStarGift artwork, persist locally, and are excluded from transactional UI. Settings titles have no emoji.
