# Changelog

## [0.2.1] — 2026-11-06
- Login (intro) screen: the paper-plane animation is replaced with the Litvin logo.
- App switcher: while the app is inactive a Litvin cover (crimson → violet gradient, logo, "Litvin") hides the chats, like banking apps do.
- Custom logo: drop a square PNG at `branding/logo.png` and it is embedded at build time into both places; without it the drawn Litvin mark is used.

## [0.2.0] — 2026-11-06
- Deleted messages: when the other side deletes a message it stays in the chat, rendered at 70% opacity with an "удалено" label next to the time. Toggle: Litvin → Удалённые сообщения.
- Protected chats/channels: copy, forward (sent as a copy), save media and screenshots/screen recording are allowed; screenshot notifications are not sent. Toggle: Litvin → Обход запрета копирования.
- View-once photos/videos/round videos/voice: can be opened any number of times; never marked as viewed, no countdown. Toggle: Litvin → Одноразовые медиа без лимита.
- All three are on by default. Wired via `scripts/litvin_patch.py` + `overlay/submodules/TelegramCore/Sources/Litvin/LitvinCore.swift`.

## [0.1.0] — 2026-11-06
- Initial scaffold.
- Build pipeline (GitHub Actions macOS runner, Bazel, unsigned IPA artifact).
- Branding: red/dark icons, splash, wordmark.
- Settings menu with toggles for every planned feature (modules are stubs; wiring patches are placeholders).
- Feature modules created with integration docs: LitvinSettings, GhostMode, ScreenshotBypass, ForwardBypass, InfiniteSelfDestruct, SaveDeleted.
