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
# Produce an unsigned IPA for AltStore / SideStore to sign at installation.
cat >> .bazelrc <<'EOF'

build --//Telegram:disableProvisioningProfiles
build --features=disable_legacy_signing
EOF
python3 build-system/Make/Make.py build \
    --configurationPath=build-system/litvin-configuration.json \
    --xcodeManagedCodesigning \
    --buildNumber=1 \
    --configuration=release_arm64
```

Export `LITVIN_API_ID` and `LITVIN_API_HASH` before running `build_config.py`.
The IPA is written to `tg-ios/bazel-bin/Telegram/Telegram.ipa`. CI uploads it as
`Litvin.ipa`. The unsigned build disables both provisioning profiles and signing;
it does not depend on Telegram's expiring fake profiles or certificates.
`--xcodeManagedCodesigning` supplies Make.py's configuration source; the Bazel
settings above disable actual signing. For a signed distribution build, use your
own signing configuration and omit these two Bazel settings.

## License

GPLv2 (inherited from Telegram-iOS).
