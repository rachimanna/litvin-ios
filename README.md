# Litvin

Unofficial Telegram client for iOS, built from Telegram-iOS at the release pinned in UPSTREAM_REF. GPLv2. No AI feature is included.

## What is implemented

Open Settings → Litvin. Privacy and collection controls are off by default; local note actions are available by default.

- Ghost controls for read receipts, typing and online presence; daily schedules, including an online window while the app is running. Ghost controls take priority over the online window.
- Sponsored-message suppression. Reopen an existing chat after changing the control.
- Screenshot controls for copy-protected cloud chats. Secret-chat and verification-code protection remains in place.
- Copy-protected cloud messages can be copied into fresh outgoing messages. The optional scrub control removes forwarding attribution and reply references.
- Local deleted-text archive and edit history with a text difference view. Saved deleted text also appears as a faded «Удалено» bubble at its timestamp in ordinary peer chats. These are non-interactive presentation entries, not messages restored on Telegram. Secret chats, forum/topic views, filtered views and encrypted archive peers are excluded from inline rendering. Only text observed by this client after collection is enabled can be recorded. Media and secret-chat content are not copied into this archive.
- Message notes, tags, colors and local reminders. Use a message's long-press menu. Nothing is synchronized through Saved Messages.
- Digest of selected channels using locally observed posts, ranked by recency with a small text-length bonus.
- Contact timeline from observed messages and explicit online/offline updates, including counts and your median response time. This is not a complete account history or a background tracker.
- Selected-chat concealment behind a separate local PIN: chat-list and search filtering, a cover for directly opened chats, and redacted new push previews. Configure a PIN in Litvin settings, then use the message menu to select chats. It does not replace Telegram's app passcode. Chats are concealed when the app loses foreground activity.
- Passphrase-encrypted Litvin history for selected chats. Moving a chat's local text/history/notes into this vault removes its ordinary Litvin copy. Encryption keys remain in memory only while the vault is open. Locked vaults do not collect new text. **Telegram's original Postbox and media cache keep their normal storage behavior; the vault does not encrypt or erase them.**
- Encrypted export/import of Litvin settings, local data, encrypted vault files, Telegram folders, theme settings, installed sticker-pack references, proxies and pinned chats. Import is restricted to the same account and asks before applying changes. Folder, pin and sticker changes synchronize through Telegram. Session credentials and login keys are excluded. Wallpaper/media files themselves are not embedded.
- Proxy pool based on Telegram's MTProto connectivity checks and round-trip times, with failover to a reachable saved proxy. Add only servers you trust; no third-party proxy feed is downloaded.
- Clean media export from the message menu: JPEG re-rendering, video re-encoding without source metadata, and optional pitch-shifted voice export. Media must already be downloaded. Voice processing does not guarantee anonymity.
- Local Premium appearance in your own profile, without changing server entitlements.
- A local display number: tap your number and choose «Изменить локальный номер». The login number and account recovery remain unchanged.
- A configurable local balance in My Stars and the settings row. Payment and purchase flows continue to use the real StarsContext balance; TON balances are unchanged.
- Local NFT gifts: choose a contact or open their profile, then add an existing t.me/nft link. Telegram supplies the original model/artwork; the client stores the choice per account and peer and adds it to the profile gift grid. These entries cannot be sold, transferred, worn, purchased or selected for collections. Remove them in «Локальные NFT-подарки». Reopen a previously empty profile to reveal its gift tab.
- Settings feature names use plain text without emoji.
- An explicitly local gift demo, visible only on your screen, with no payment or gift RPC.

One-time media viewing suppresses this client's consumed-content notification and gallery timeout UI. It cannot reverse expiry or deletion already performed by Telegram or another client.

## Project layout

- features/LitvinCore: persistent policies, account-separated local data, PIN protection, authenticated encryption and encrypted local history.
- features/LitvinSettings: native controls and tools, media processing, backup UI and proxy management.
- overlay/submodules/TelegramCore/Sources: small typed adapters for message capture and Telegram context export/import.
- scripts/litvin_patch.py: inserts the Litvin settings entry.
- scripts/feature_patches.py: checked source integration anchors for the pinned Telegram release.
- branding: SVG assets and display-name replacements.

## Build and install

The upstream release currently targets iOS 15 or later. A macOS machine with the Xcode version declared by upstream versions.json is required.

Set LITVIN_API_ID and LITVIN_API_HASH as GitHub repository secrets, or export them locally. Do not commit API credentials.

```bash
git clone https://github.com/rachimanna/litvin-ios.git
cd litvin-ios
bash scripts/setup.sh
cd tg-ios
bash ../scripts/apply_overlay.sh
bash ../scripts/apply_patches.sh
python3 ../scripts/build_config.py ../overlay/litvin-configuration.json build-system/litvin-configuration.json
python3 build-system/Make/ImportCertificates.py --path build-system/fake-codesigning/certs
python3 ../scripts/refresh_fake_profiles.py "$PWD"
python3 build-system/Make/Make.py build \
    --configurationPath=build-system/litvin-configuration.json \
    --codesigningInformationPath=build-system/fake-codesigning \
    --buildNumber=1 --configuration=release_arm64
```

The IPA is produced at tg-ios/bazel-bin/Telegram/Telegram.ipa. GitHub Actions uploads it as Litvin.ipa. This is a test-signed build using upstream's ph.telegra.Telegraph identity; AltStore / SideStore or your own Apple signing setup must re-sign it for installation. The on-device name is Litvin; the new Gram G-and-wing mark is installed as the app icon and shown on the phone-entry screen. branding/avatar.svg is the matching avatar.

## ESign distribution

After the main IPA build succeeds, open GitHub Actions → **Publish IPA for ESign** → **Run workflow**. Leave run_id empty to publish the latest successful main build, or provide a successful main Build Litvin iOS run ID. This manual control publishes Litvin.ipa, its SHA-256 checksum, an icon and esign-source.json together in a GitHub Release. It never publishes a failed build or a pull-request build.

On the iPhone, use Settings → Litvin → **Установка через ESign** to download the published IPA or copy the source URL. Import the IPA into ESign, sign it with your own valid certificate and provisioning profile, then install. No certificate or private signing key is stored in this repository.

Source URL after the first publication: https://github.com/rachimanna/litvin-ios/releases/latest/download/esign-source.json

The JSON uses the [app-source format documented by the ESign repo builder](https://github.com/Aussielad89/esign-repo#index-format-esign_sourcejson). Manual IPA import remains available if a particular ESign version does not accept the source format.

## Checks

```bash
python3 -m unittest discover -s scripts/tests -v
python3 scripts/verify_integration.py
```

The validation workflow additionally typechecks LitvinCore with the iOS SDK, runs its behavior tests on macOS, and parses the Swift additions. The IPA workflow compiles the integrated client. Validation runs once per PR update; superseded runs in the same PR are cancelled.
