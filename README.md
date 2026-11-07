# Litvin

Unofficial Telegram client for iOS. Fork of [Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS) with extended features and custom branding.

- **Package:** `app.litvin.messenger`
- **Platform:** iOS 12.0+
- **Base:** Telegram-iOS, pinned to a tagged release (see `scripts/setup.sh`)
- **Build:** Bazel on GitHub Actions macOS runner
- **Install:** AltStore / SideStore / TrollStore / self-signed with Apple Dev account

---

## Repo layout

```
.
├── .github/workflows/build.yml    # CI: clone TG-iOS, overlay, build IPA
├── scripts/
│   ├── setup.sh                   # clone Telegram-iOS at pinned tag
│   ├── apply_overlay.sh           # copy branding + features into TG-iOS tree
│   └── apply_patches.sh           # apply unified diffs against pinned tag
├── branding/
│   ├── icon.svg                   # app icon source (1024x1024)
│   ├── icon-dark.svg              # dark variant
│   ├── splash.svg                 # login screen logo
│   ├── strings.json               # Telegram → Litvin string map
│   └── generate_icons.sh          # svg → every required iOS size
├── overlay/                       # files that OVERLAY onto TG-iOS tree
├── patches/                       # unified-diff patches against pinned commit
└── features/                      # Litvin feature modules
    ├── LitvinSettings/            # top-level settings menu "Litvin"
    ├── GhostMode/                 # no read/typing/online receipts
    ├── SaveDeleted/               # local store of deleted + edited messages
    ├── ScreenshotBypass/          # take screenshots in protected chats
    ├── ForwardBypass/             # forward from no-forward chats
    ├── InfiniteSelfDestruct/      # view one-time media without timer
    ├── DoubleBottom/              # second PIN hides chats/accounts
    ├── AntiAds/                   # strip sponsored messages in channels
    ├── EditHistory/               # full edit history timeline
    ├── GhostSchedule/             # scheduled fake online + alibi activity
    ├── MessageNotes/              # personal tags on others' messages
    ├── ChannelDigest/             # ranked digest of N channels
    ├── ContactProfile/            # auto-built timeline per contact
    ├── ForwardScrub/              # strip forward meta + EXIF + voice fingerprint
    ├── ChatVault/                 # chats encrypted under a second passphrase
    ├── ProxyPool/                 # built-in MTProto proxy rotator
    ├── ContextExport/             # export/import full client state
    └── LocalAI/                   # on-device LLM (llama.cpp binding)
```

## Features

### From AyuGram / Nagram / exteraGram family
- Ghost mode (no read / typing / online)
- Save deleted messages
- Save edit history
- Anti-ads in channels
- Double bottom (second PIN hides accounts/chats)
- Hide chats / accounts
- Local premium unlock where client-side only

### Litvin-exclusive
- **Screenshot bypass** — capture screens in chats with `noforwards`
- **Forward bypass** — forward from protected chats
- **Infinite self-destruct** — view one-time photo/video with no timer, optional save
- **Local AI** — on-device summarize / draft / semantic search (no cloud)
- **Edit history timeline** — see every past version of an edited message with diff
- **Scheduled ghost + alibi** — fake online patterns on a schedule
- **Message notes** — private tags/colors/reminders on others' messages, synced via Saved Messages
- **Channel digest** — N channels collapse into one ranked feed
- **Contact profile** — auto timeline per contact (online pattern, response time, tone)
- **Forward scrub** — on forward, zero out "forwarded from", nested quotes, EXIF, voice fingerprint
- **Chat vault** — selected chats encrypted under a second passphrase, invisible when locked
- **Proxy pool** — built-in MTProto proxy rotator with liveness/speed checks
- **Context export** — one file with folders, themes, stickers, settings, pins

### Branding
- App icon: white Λ + crossbar on deep red (Pahonia-cross monogram)
- Login splash: Litvin mark in place of Telegram's dove animation
- Chat list header: "Litvin" title with accent color (like Sberbank yellow bar / Telegram blue)
- Navigation bar tint: accent red `#C8102E`
- Settings → new top section **Litvin** with every toggle above

## Install on device

### Option 1 — AltStore / SideStore (free, 7-day re-sign)
1. Install AltServer on a computer, pair with device.
2. Download `Litvin.ipa` from the latest CI run's artifacts.
3. Open with AltStore on the device, sign with your Apple ID.
4. Re-sign every 7 days (AltStore does it in background on same Wi-Fi).

### Option 2 — TrollStore (iOS 14.0–16.6.1, permanent)
1. Install TrollStore via the method for your iOS version.
2. Open the `Litvin.ipa` in TrollStore. Done, no re-signing.

### Option 3 — Jailbreak
Install the IPA via Filza / AppSync. Permanent.

### Option 4 — Apple Dev account ($99/year)
Open the project in Xcode, set your team, sign, archive, distribute ad-hoc.

## Build locally (macOS)

```bash
git clone https://github.com/rachimanna/litvin-ios.git
cd litvin-ios
bash scripts/setup.sh        # clones Telegram-iOS at pinned tag into ./tg-ios
cd tg-ios
bash ../scripts/apply_overlay.sh
bash ../scripts/apply_patches.sh
python3 ../scripts/build_config.py \
    ../overlay/litvin-configuration.json build-system/litvin-configuration.json
# Prepare upstream's test signing assets for a sideloadable build.
python3 build-system/Make/ImportCertificates.py --path build-system/fake-codesigning/certs
python3 ../scripts/refresh_fake_profiles.py "$PWD"
python3 build-system/Make/Make.py build \
    --configurationPath=build-system/litvin-configuration.json \
    --codesigningInformationPath=build-system/fake-codesigning \
    --buildNumber=1 \
    --configuration=release_arm64
```

Export `LITVIN_API_ID` and `LITVIN_API_HASH` before running `build_config.py`.
The IPA is written to `tg-ios/bazel-bin/Telegram/Telegram.ipa`. CI uploads it as
`Litvin.ipa`. The build uses Telegram's self-signed test identity and refreshes
expired test profiles before Bazel validates them. This does not create a valid
Apple distribution signature: AltStore / SideStore must re-sign the IPA for your
device. For a distribution build, supply your own valid Apple signing assets.

## License

GPLv2 (inherited from Telegram-iOS).


## Локальное оформление (1.4.1)

Настройки → Litvin → «Оформление, номер и звёзды» / «Подарки без списания звёзд».

- Premium: значок и оформление собственного профиля, без изменения подписки на сервере.
- Номер: нажми свой номер → «Изменить локальный номер». Можно вернуть настоящий номер, очистив поле. Номер для входа не меняется.
- Звёзды: локальное число в «Мои звёзды», строке настроек и «Балансе» справа сверху в каталоге подарков. Покупки, переводы и TON используют настоящий баланс.
- Подарки: профиль собеседника → «Отправить подарок» → карточка подарка. Вкладка NFT открывает коллекции и варианты без ввода ссылок; обычный подарок добавляется одним нажатием. Выбор сохраняется только на этом устройстве. Для обычной отправки отключи «Подарки без списания звёзд». Убрать копию можно долгим нажатием в профиле.
- Названия функций в настройках отображаются без эмодзи.

Раздел «Сбросить локальное оформление» возвращает исходные значения и убирает локальные подарки. Это не восстанавливает сообщения и не меняет реальное владение NFT.

Проверки: `python3 scripts/verify_appearance.py` проверяет повторное применение патчей к закреплённому upstream. Workflow Validate local appearance проверяет Swift, iOS Foundation и изоляцию локальных настроек. Полную компиляцию клиента выполняет Build Litvin iOS.


## Build base: Telegram 13.0.0

UPSTREAM_REF is pinned to `release-13.0.0`. CI uses macOS 26 and selects the Xcode version in upstream versions.json (26.6). The 13.1-specific mergedServerMessageUpdate adapter is removed; remote edit history uses the 13.0 patch path. Appearance patches tolerate both public and restricted Postbox BUILD layouts. Run `python3 scripts/verify_runtime.py` and `python3 scripts/verify_appearance.py` to verify source anchors and repeatability before building.


## Native gift flow

The separate UIKit gift picker and profile tool row are removed. Gifts are selected in Telegram’s original GiftOptionsScreen and resale store. Settings → Litvin → «Подарки без списания звёзд» enables private previews; fresh accounts default to disabled, and existing appearance data without this field keeps the previous preview mode. In preview mode a standard gift is added on selection; NFT selection uses the native resale detail/send flow, without payment RPCs. Disable the switch for normal Telegram sending.

Profile gifts open the native GiftViewScreen. The pager derives its items and selected index from one snapshot, including private entries; a stale tap opens that exact gift alone. Private copies show the recipient as owner, the account as sender, and a default display listing price of 1,000 Stars. They use the native detail layout and Close button. Real owned gifts keep their real metadata and original actions. Private entries never invoke sale, transfer, wear, crafting, offer or payment RPCs. Long press removes a private entry.
