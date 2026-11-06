#!/usr/bin/env python3
"""
Anchor-based source edits for Telegram-iOS. Each edit inserts a snippet after
a regex anchor, is idempotent, and fails loudly if the anchor is missing.

Usage: python3 litvin_patch.py <tg-ios-root>
"""
import base64
import re
import sys
from pathlib import Path

PEERINFO = "submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen"


def insert_after(text, pattern, snippet, label):
    if snippet in text:
        return text
    match = re.search(pattern, text, re.MULTILINE)
    if match is None:
        raise SystemExit(f"[litvin_patch] anchor not found ({label}): {pattern!r}")
    return text[:match.end()] + snippet + text[match.end():]


def add_import(text, module, label):
    line = f"import {module}\n"
    if line in text:
        return text
    imports = list(re.finditer(r"^import [^\n]+\n", text, re.MULTILINE))
    if not imports:
        raise SystemExit(f"[litvin_patch] no imports found ({label})")
    pos = imports[-1].end()
    return text[:pos] + line + text[pos:]


def replace_once(text, old, new, label):
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"[litvin_patch] expected 1 occurrence, found {count} ({label}): {old[:80]!r}")
    return text.replace(old, new)


PROTECTION_RE = re.compile(
    r"(?<![\w.])(?<!LitvinFlags\.bypassProtection && )"
    r"(?:[A-Za-z_]\w*\.)+flags\.contains\(\.(?:copyProtectionEnabled|myCopyProtectionEnabled|CopyProtected)\)"
)


def bypass_protection_checks(expected, region=None):
    """Wrap every copy-protection flag read in the file (or in the first match
    of `region`) with the Litvin switch."""
    def fn(text, label):
        start, end = 0, len(text)
        if region is not None:
            match = re.search(region, text)
            if match is None:
                raise SystemExit(f"[litvin_patch] region not found ({label}): {region!r}")
            start, end = match.span()
        body, count = PROTECTION_RE.subn(lambda m: f"(!LitvinFlags.bypassProtection && {m.group(0)})", text[start:end])
        text = text[:start] + body + text[end:]
        if count == 0 and "LitvinFlags.bypassProtection" in text:
            return text
        if count != expected:
            raise SystemExit(f"[litvin_patch] expected {expected} protection checks, wrapped {count} ({label})")
        return text
    return fn


def edit(root, rel, fn):
    path = root / rel
    original = path.read_text(encoding="utf-8")
    updated = fn(original, rel)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
        print(f"[litvin_patch] patched {rel}")
    else:
        print(f"[litvin_patch] already patched {rel}")


def patch_build(text, label):
    return insert_after(
        text,
        r"^\s*deps = \[\n",
        '        "//submodules/LitvinFeatures/LitvinSettings:LitvinSettings",\n',
        label,
    )


def patch_section_enum(text, label):
    return insert_after(text, r"^enum PeerInfoSettingsSection \{\n", "    case litvin\n", label)


def patch_settings_items(text, label):
    text = add_import(text, "LitvinSettings", label)
    text = insert_after(text, r"^enum SettingsSection: Int, CaseIterable \{\n", "    case litvin\n", label)
    text = insert_after(
        text,
        r"^    for section in SettingsSection\.allCases \{\n\s*items\[section\] = \[\]\n\s*\}\n",
        "    items[.litvin]!.append(PeerInfoScreenDisclosureItem(id: 0, text: \"Litvin\", icon: litvinSettingsRowIcon(), action: {\n"
        "        interaction.openSettings(.litvin)\n"
        "    }))\n",
        label,
    )
    return text


def patch_settings_actions(text, label):
    text = add_import(text, "LitvinSettings", label)
    return insert_after(
        text,
        r"func openSettings\(section: PeerInfoSettingsSection\) \{[\s\S]*?^        switch section \{\n",
        "        case .litvin:\n"
        "            push(litvinSettingsController(context: self.context))\n",
        label,
    )


# ---------------------------------------------------------------------------
# Deleted messages: keep remotely deleted messages, mark them in the chat.
# ---------------------------------------------------------------------------

def patch_register_deleted_attribute(text, label):
    return insert_after(
        text,
        r"^\s*declareEncodable\(ContentRequiresValidationMessageAttribute\.self[^\n]*\n",
        "    declareEncodable(LitvinDeletedMessageAttribute.self, f: { LitvinDeletedMessageAttribute(decoder: $0) })\n"
        "    declareEncodable(LitvinEditHistoryMessageAttribute.self, f: { LitvinEditHistoryMessageAttribute(decoder: $0) })\n",
        label,
    )


def patch_remote_delete(text, label):
    text = replace_once(
        text,
        "transaction.deleteMessagesWithGlobalIds(ids, forEachMedia:",
        "transaction.deleteMessagesWithGlobalIds(litvinFilterDeletedGlobalIds(transaction: transaction, ids: ids), forEachMedia:",
        label,
    )
    text = replace_once(
        text,
        "                _internal_deleteMessages(transaction: transaction, mediaBox: mediaBox, ids: ids, manualAddMessageThreadStatsDifference:",
        "                _internal_deleteMessages(transaction: transaction, mediaBox: mediaBox, ids: litvinFilterDeletedMessageIds(transaction: transaction, ids: ids), manualAddMessageThreadStatsDifference:",
        label,
    )
    return text


def patch_deleted_status_text(text, label):
    return replace_once(
        text,
        "    var authorTitle: String?\n",
        "    if message._asMessage().litvinIsDeleted {\n"
        "        dateText = \"удалено \" + dateText\n"
        "    }\n"
        "\n"
        "    var authorTitle: String?\n",
        label,
    )


def patch_deleted_alpha(text, label):
    return replace_once(
        text,
        "    open func setupItem(_ item: ChatMessageItem, synchronousLoad: Bool) {\n        self.item = item\n",
        "    open func setupItem(_ item: ChatMessageItem, synchronousLoad: Bool) {\n        self.item = item\n"
        "        self.alpha = item.message.litvinIsDeleted ? 0.7 : 1.0\n",
        label,
    )


# ---------------------------------------------------------------------------
# Protected chats: copy / forward / save / screenshots.
# ---------------------------------------------------------------------------

def patch_content_data_protection(text, label):
    return replace_once(
        text,
        "copyProtectionEnabled = cachedUserData.flags.contains(.copyProtectionEnabled) || cachedUserData.flags.contains(.myCopyProtectionEnabled)\n",
        "copyProtectionEnabled = !LitvinFlags.bypassProtection && (cachedUserData.flags.contains(.copyProtectionEnabled) || cachedUserData.flags.contains(.myCopyProtectionEnabled))\n",
        label,
    )


def patch_forward_as_copy(text, label):
    text = insert_after(
        text,
        r"private func forwardedMessageToBeReuploaded\(transaction: Transaction, id: MessageId\) -> Message\? \{\n\s*if let message = transaction\.getMessage\(id\) \{\n",
        "        if LitvinFlags.bypassProtection && message.id.namespace == Namespaces.Message.Cloud && litvinIsRawCopyProtected(transaction: transaction, message: message) {\n"
        "            return message\n"
        "        }\n",
        label,
    )
    text = insert_after(
        text,
        r"if sourceMessage\.id\.peerId\.namespace == Namespaces\.Peer\.SecretChat \{\n\s*if let media = sourceMessage\.media\.first \{\n\s*mediaReference = \.standalone\(media: media\)\n\s*\}\n\s*\}\n",
        "                    if mediaReference == nil, sourceMessage.id.namespace == Namespaces.Message.Cloud, let media = sourceMessage.media.first(where: { $0 is TelegramMediaImage || $0 is TelegramMediaFile }) {\n"
        "                        mediaReference = .message(message: MessageReference(sourceMessage), media: media)\n"
        "                    }\n",
        label,
    )
    return text


def patch_layer_screenshots(text, label):
    return insert_after(
        text,
        r"void setLayerDisableScreenshots\(CALayer \* _Nonnull layer, bool disableScreenshots\) \{\n",
        "    if (disableScreenshots && ![[NSUserDefaults standardUserDefaults] boolForKey:@\"litvin.off.bypassProtection\"]) {\n"
        "        disableScreenshots = false;\n"
        "    }\n",
        label,
    )


def patch_screenshot_detection(text, label):
    snippet_guard = "UserDefaults.standard.bool(forKey: \"litvin.off.bypassProtection\")"
    text = insert_after(
        text,
        r"public func screenCaptureEvents\(\) -> Signal<ScreenCaptureEvent, NoError> \{\n",
        f"    if !{snippet_guard} {{\n        return .never()\n    }}\n",
        label,
    )
    text = insert_after(
        text,
        r"public final class ScreenCaptureDetectionManager \{[\s\S]*?public init\(check: @escaping \(\) -> Bool\) \{\n",
        f"        if !{snippet_guard} {{\n            return\n        }}\n",
        label,
    )
    return text


# ---------------------------------------------------------------------------
# View-once media: never mark as consumed, so no countdown and no deletion.
# ---------------------------------------------------------------------------

def patch_view_once(text, label):
    return insert_after(
        text,
        r"func _internal_markMessageContentAsConsumedInteractively\(postbox: Postbox, messageId: MessageId\) -> Signal<Void, NoError> \{\n"
        r"\s*return postbox\.transaction \{ transaction -> Void in\n"
        r"\s*if let message = transaction\.getMessage\(messageId\), message\.flags\.contains\(\.Incoming\) \{\n",
        "            if LitvinFlags.unlimitedViewOnce && message.containsSecretMedia {\n"
        "                return\n"
        "            }\n",
        label,
    )


# ---------------------------------------------------------------------------
# Branding: intro (login) logo + app-switcher cover.
# ---------------------------------------------------------------------------

INTRO_LOGO_C = r"""
// Litvin: crimson disc with the white Litvin mark, replaces the paper plane.
static UIImage *LitvinIntroLogoImage(CGFloat size) {
    if (size < 1.0) {
        size = 200.0;
    }
    if (LitvinCustomLogoBase64.length != 0) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:LitvinCustomLogoBase64 options:0];
        UIImage *custom = data != nil ? [UIImage imageWithData:data] : nil;
        if (custom != nil) {
            return custom;
        }
    }
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        CGContextRef context = rendererContext.CGContext;
        CGRect circleRect = CGRectInset(CGRectMake(0.0, 0.0, size, size), size * 0.04, size * 0.04);

        CGContextSaveGState(context);
        CGContextAddEllipseInRect(context, circleRect);
        CGContextClip(context);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGFloat components[12] = {
            0xE0 / 255.0, 0x16 / 255.0, 0x3A / 255.0, 1.0,
            0x9E / 255.0, 0x12 / 255.0, 0x50 / 255.0, 1.0,
            0x4B / 255.0, 0x16 / 255.0, 0x83 / 255.0, 1.0
        };
        CGFloat locations[3] = {0.0, 0.55, 1.0};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, components, locations, 3);
        CGContextDrawLinearGradient(context, gradient, CGPointMake(CGRectGetMinX(circleRect), CGRectGetMinY(circleRect)), CGPointMake(CGRectGetMaxX(circleRect), CGRectGetMaxY(circleRect)), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(colorSpace);
        CGContextRestoreGState(context);

        CGFloat scale = circleRect.size.width * 0.56 / 544.0;
        CGFloat left = CGRectGetMidX(circleRect) - 272.0 * scale;
        CGFloat top = CGRectGetMidY(circleRect) - 552.0 * scale / 2.0;

        CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
        CGContextSetLineWidth(context, 88.0 * scale);
        CGContextSetLineCap(context, kCGLineCapSquare);
        CGContextSetLineJoin(context, kCGLineJoinMiter);
        CGContextMoveToPoint(context, left, top + 552.0 * scale);
        CGContextAddLineToPoint(context, left + 272.0 * scale, top);
        CGContextAddLineToPoint(context, left + 544.0 * scale, top + 552.0 * scale);
        CGContextStrokePath(context);
        CGContextMoveToPoint(context, left + 104.0 * scale, top + 344.0 * scale);
        CGContextAddLineToPoint(context, left + 440.0 * scale, top + 344.0 * scale);
        CGContextStrokePath(context);
    }];
}
"""


def custom_logo_base64():
    """branding/logo.png (if present) is embedded into the binary as base64."""
    path = Path(__file__).resolve().parent.parent / "branding" / "logo.png"
    if path.is_file():
        print(f"[litvin_patch] embedding custom logo {path} ({path.stat().st_size} bytes)")
        return base64.b64encode(path.read_bytes()).decode("ascii")
    print("[litvin_patch] no branding/logo.png, using drawn Litvin logo")
    return ""


def patch_intro_logo(text, label):
    logo = custom_logo_base64()
    text = insert_after(
        text,
        r"#import <LegacyComponents/LegacyComponents\.h>\n",
        f"\nstatic NSString *const LitvinCustomLogoBase64 = @\"{logo}\";\n" + INTRO_LOGO_C,
        label,
    )
    text = insert_after(
        text,
        r"\[self setupGL\];\n\s*\[self\.view addSubview:_glkView\];\n",
        "        {\n"
        "            UIImageView *litvinLogoView = [[UIImageView alloc] initWithFrame:_glkView.bounds];\n"
        "            litvinLogoView.image = LitvinIntroLogoImage(_glkView.bounds.size.width);\n"
        "            litvinLogoView.contentMode = UIViewContentModeScaleAspectFit;\n"
        "            litvinLogoView.backgroundColor = _backgroundColor;\n"
        "            litvinLogoView.opaque = true;\n"
        "            litvinLogoView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;\n"
        "            [_glkView addSubview:litvinLogoView];\n"
        "        }\n",
        label,
    )
    return replace_once(
        text,
        "    UIImage *image = _glkView.snapshot;\n",
        "    UIImage *image = LitvinIntroLogoImage(_glkView.bounds.size.width);\n",
        label,
    )


def write_custom_logo_swift(root):
    out = root / "submodules/TelegramUI/Sources/Litvin/LitvinCustomLogo.swift"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        "// Generated by scripts/litvin_patch.py from branding/logo.png. Do not edit.\n"
        f"let litvinCustomLogoBase64: String = \"{custom_logo_base64()}\"\n",
        encoding="utf-8",
    )
    print(f"[litvin_patch] wrote {out.relative_to(root)}")


def patch_privacy_cover(text, label):
    return insert_after(
        text,
        r"^        self\.nativeWindow = window\n",
        "        LitvinPrivacyCover.shared.install(window: window)\n"
        "        LitvinTopBadge.shared.install(window: window)\n",
        label,
    )


# ---------------------------------------------------------------------------
# Ghost mode: no read receipts, typing, "listened" or online status.
# ---------------------------------------------------------------------------

def wrap_calls(start, wrapper, expected):
    """Wrap every `start...)` call expression (balanced parens) as `wrapper(<call>)`."""
    def fn(text, label):
        if f"{wrapper}({start}" in text:
            return text
        out = []
        pos = 0
        count = 0
        while True:
            idx = text.find(start, pos)
            if idx < 0:
                break
            depth = 0
            end = None
            for j in range(idx + start.index("("), len(text)):
                ch = text[j]
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth == 0:
                        end = j + 1
                        break
            if end is None:
                raise SystemExit(f"[litvin_patch] unbalanced call ({label}): {start!r}")
            out.append(text[pos:idx])
            out.append(f"{wrapper}({text[idx:end]})")
            pos = end
            count += 1
        out.append(text[pos:])
        if count != expected:
            raise SystemExit(f"[litvin_patch] expected {expected} calls of {start!r}, found {count} ({label})")
        return "".join(out)
    return fn


def chain(*fns):
    def fn(text, label):
        for f in fns:
            text = f(text, label)
        return text
    return fn


def patch_ghost_presence(text, label):
    return insert_after(
        text,
        r"    private func updatePresence\(_ isOnline: Bool\) \{\n",
        "        if LitvinFlags.ghostMode {\n"
        "            self.onlineTimer?.invalidate()\n"
        "            self.onlineTimer = nil\n"
        "            return\n"
        "        }\n",
        label,
    )


# ---------------------------------------------------------------------------
# Voice changer: voice/video messages (Swift) and 1:1 calls (tgcalls C++).
# ---------------------------------------------------------------------------

def patch_voice_recorder(text, label):
    text = insert_after(
        text,
        r"    private var micLevelPeak: Int16 = 0\n",
        "    private let litvinVoiceChanger = LitvinVoiceChanger(sampleRate: 48000.0)\n",
        label,
    )
    return replace_once(
        text,
        "            } else {\n                self.processWaveformPreview(samples: currentEncoderPacket.assumingMemoryBound(to: Int16.self), count: currentEncoderPacketSize / 2)\n",
        "            } else {\n                self.litvinVoiceChanger.process(currentEncoderPacket.assumingMemoryBound(to: Int16.self), count: currentEncoderPacketSize / 2)\n"
        "                self.processWaveformPreview(samples: currentEncoderPacket.assumingMemoryBound(to: Int16.self), count: currentEncoderPacketSize / 2)\n",
        label,
    )


def patch_call_voice(text, label):
    if "litvin::CreateVoiceChangerProcessing" in text:
        return text
    text, count = re.subn(
        r"^(\s*)(webrtc::\s*AudioProcessingBuilder builder;\n)",
        lambda m: m.group(1) + m.group(2) + m.group(1) + "builder.SetCapturePostProcessing(litvin::CreateVoiceChangerProcessing());\n",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise SystemExit(f"[litvin_patch] AudioProcessingBuilder not found ({label})")
    first_include = re.search(r"^#include [^\n]+\n", text, re.MULTILINE)
    if first_include is None:
        raise SystemExit(f"[litvin_patch] no #include ({label})")
    pos = first_include.end()
    return text[:pos] + "#include \"utils/LitvinVoiceProcessing.h\"\n" + text[pos:]


def wrap_call_argument(call_start, wrapper, expected):
    """`f(<arg>)` -> `f(wrapper(<arg>))` for every call starting with `call_start` (ends at its '(')."""
    def fn(text, label):
        if f"{call_start}{wrapper}(" in text:
            return text
        out, pos, count = [], 0, 0
        while True:
            idx = text.find(call_start, pos)
            if idx < 0:
                break
            open_idx = idx + len(call_start) - 1
            depth, end = 0, None
            for j in range(open_idx, len(text)):
                if text[j] == "(":
                    depth += 1
                elif text[j] == ")":
                    depth -= 1
                    if depth == 0:
                        end = j
                        break
            if end is None:
                raise SystemExit(f"[litvin_patch] unbalanced call ({label}): {call_start!r}")
            out.append(text[pos:open_idx + 1])
            out.append(f"{wrapper}({text[open_idx + 1:end]})")
            pos = end
            count += 1
        out.append(text[pos:])
        if count != expected:
            raise SystemExit(f"[litvin_patch] expected {expected} calls of {call_start!r}, found {count} ({label})")
        return "".join(out)
    return fn


def add_cpp_include(header):
    def fn(text, label):
        line = f'#include "{header}"\n'
        if line in text:
            return text
        first = re.search(r"^#include [^\n]+\n", text, re.MULTILINE)
        if first is None:
            raise SystemExit(f"[litvin_patch] no #include ({label})")
        return text[:first.end()] + line + text[first.end():]
    return fn


def patch_group_call_fallback(text, label):
    # When Telegram installs no post-processor (no audio-level callback), add ours alone.
    return insert_after(
        text,
        r"            peerConnectionFactoryDeps\.audio_processing = builder\.Create\(\);\n        \}\n#endif\n",
        "        if (!peerConnectionFactoryDeps.audio_processing) {\n"
        "            if (auto litvinVoice = litvin::CreateVoiceChangerProcessing()) {\n"
        "                webrtc::AudioProcessingBuilder litvinBuilder;\n"
        "                litvinBuilder.SetCapturePostProcessing(std::move(litvinVoice));\n"
        "                peerConnectionFactoryDeps.audio_processing = litvinBuilder.Create();\n"
        "            }\n"
        "        }\n",
        label,
    )


# ---------------------------------------------------------------------------
# App name shown by iOS (home screen, app switcher header, Settings).
# ---------------------------------------------------------------------------

def patch_app_display_name(text, label):
    if "<string>Litvin</string>" in text:
        return text
    text, count = re.subn(
        r"(<key>CFBundleDisplayName</key>\s*<string>)Telegram(</string>)",
        r"\1Litvin\2",
        text,
    )
    if count < 1:
        raise SystemExit(f"[litvin_patch] CFBundleDisplayName not found ({label})")
    text = re.sub(r"(<key>CFBundleName</key>\s*<string>)Telegram(</string>)", r"\1Litvin\2", text)
    return text


def patch_localized_display_name(text, label):
    return re.sub(r'^"CFBundleDisplayName" = "[^"]*";', '"CFBundleDisplayName" = "Litvin";', text, flags=re.MULTILINE)


# ---------------------------------------------------------------------------
# Final update: no ads, edit history, read-for-them, chat stats, confetti,
# on-device transcription, auto-reply.
# ---------------------------------------------------------------------------

def patch_anti_ads(text, label):
    return replace_once(
        text,
        "            guard let inputPeer else {\n                return .single((nil, nil, nil, []))\n            }\n            var flags: Int32 = 0\n",
        "            guard let inputPeer, !LitvinFlags.antiAds else {\n                return .single((nil, nil, nil, []))\n            }\n            var flags: Int32 = 0\n",
        label,
    )


def patch_edit_history_core(text, label):
    merged = "return .update(mergedServerMessageUpdate(previous: previousMessage, updated: message))"
    if merged in text or "litvinApplyEditHistory(previous: previousMessage, merged:" in text:
        # Telegram 13.1+
        return replace_once(
            text,
            merged,
            "return .update(litvinApplyEditHistory(previous: previousMessage, merged: mergedServerMessageUpdate(previous: previousMessage, updated: message)))",
            label,
        )
    return insert_after(
        text,
        r"case let \.EditMessage\(id, message\):\n[^\n]*\n\s*transaction\.updateMessage\(id, update: \{ previousMessage in\n[^\n]*\n[^\n]*\n\s*var updatedAttributes = message\.attributes\n",
        "                    litvinApplyEditHistory(previous: previousMessage, newText: message.text, attributes: &updatedAttributes)\n",
        label,
    )


EDIT_HISTORY_MENU = """        if messages.count == 1, let litvinHistory = messages[0].litvinEditHistory, !litvinHistory.versions.isEmpty {
            let litvinMessage = messages[0]
            actions.append(.action(ContextMenuActionItem(text: "История правок (\\(litvinHistory.versions.count))", icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Edit"), color: theme.actionSheet.primaryTextColor)
            }, action: { c, _ in
                c?.dismiss(completion: {
                    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                    controllerInteraction.presentController(textAlertController(context: context, title: "История правок", text: litvinEditHistoryText(litvinHistory, current: litvinMessage.text), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
                })
            })))
        }

"""


def patch_edit_history_menu(text, label):
    return replace_once(
        text,
        "        if !isPinnedMessages, !isReplyThreadHead, data.canReply {\n",
        EDIT_HISTORY_MENU + "        if !isPinnedMessages, !isReplyThreadHead, data.canReply {\n",
        label,
    )


CHAT_LIST_MENU = """                        if peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup || peerId.namespace == Namespaces.Peer.CloudChannel {
                            if LitvinFlags.ghostMode {
                                items.append(.action(ContextMenuActionItem(text: "Прочитать для собеседника", icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Read"), color: theme.contextMenu.primaryColor) }, action: { _, f in
                                    let _ = litvinForceReadHistory(account: context.account, peerId: peerId).startStandalone()
                                    f(.default)
                                })))
                            }
                            items.append(.action(ContextMenuActionItem(text: "Статистика переписки", icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Statistics"), color: theme.contextMenu.primaryColor) }, action: { _, f in
                                f(.default)
                                chatListController?.push(litvinChatStatsController(context: context, peerId: peerId))
                            })))
                        }

"""


def patch_chat_list_menu(text, label):
    text = add_import(text, "LitvinSettings", label)
    return replace_once(
        text,
        "                        if !isCommunity {\n                            if isUnread {\n",
        CHAT_LIST_MENU + "                        if !isCommunity {\n                            if isUnread {\n",
        label,
    )


def patch_chat_list_build(text, label):
    return insert_after(
        text,
        r"^\s*deps = \[\n",
        '        "//submodules/LitvinFeatures/LitvinSettings:LitvinSettings",\n',
        label,
    )


def patch_confetti(text, label):
    return insert_after(
        text,
        r"    func sendMessages\(_ messages: \[EnqueueMessage\], media: Bool = false, postpone: Bool = false, commit: Bool = false\) \{\n",
        "        if litvinShouldPlayConfetti(messages) {\n"
        "            Queue.mainQueue().after(0.25, { [weak self] in\n"
        "                self?.chatDisplayNode.playConfettiAnimation()\n"
        "            })\n"
        "        }\n",
        label,
    )


def patch_local_transcription(text, label):
    text = replace_once(
        text,
        "                    if arguments.associatedData.isPremium || arguments.associatedData.alwaysDisplayTranscribeButton.providedByGroupBoost {\n                        displayTranscribe = true\n",
        "                    if LitvinFlags.localTranscription || arguments.associatedData.isPremium || arguments.associatedData.alwaysDisplayTranscribeButton.providedByGroupBoost {\n                        displayTranscribe = true\n",
        label,
    )
    text = replace_once(
        text,
        "        if transcriptionText == nil && !arguments.associatedData.alwaysDisplayTranscribeButton.providedByGroupBoost {\n",
        "        if transcriptionText == nil && !arguments.associatedData.alwaysDisplayTranscribeButton.providedByGroupBoost && !LitvinFlags.localTranscription {\n",
        label,
    )
    text = replace_once(
        text,
        "                if context.sharedContext.immediateExperimentalUISettings.localTranscription {\n",
        "                if context.sharedContext.immediateExperimentalUISettings.localTranscription || (LitvinFlags.localTranscription && !arguments.associatedData.isPremium) {\n",
        label,
    )
    return text


def patch_auto_reply(text, label):
    return insert_after(
        text,
        r"^        self\.managedOperationsDisposable\.add\(managedCloudChatRemoveMessagesOperations\([^\n]*\n",
        "        self.managedOperationsDisposable.add(litvinManagedAutoReply(account: self).start())\n",
        label,
    )


# ---------------------------------------------------------------------------
# App icon (iOS 26 Icon Composer bundle Telegram/Telegram-iOS/Telegram.icon).
# The plane layer becomes the Litvin "L", the blue oval a full black square.
# ---------------------------------------------------------------------------

def install_icon_composer(root):
    src = Path(__file__).resolve().parent.parent / "branding" / "icon-composer"
    icon = root / "Telegram/Telegram-iOS/Telegram.icon"
    if not icon.is_dir() or not src.is_dir():
        print("[litvin_patch] Telegram.icon or branding/icon-composer missing; icon not replaced")
        return
    for name in ("Plane.svg", "Oval.svg"):
        (icon / "Assets" / name).write_text((src / name).read_text(encoding="utf-8"), encoding="utf-8")
    js = icon / "icon.json"
    text = js.read_text(encoding="utf-8")
    text = re.sub(r'"linear-gradient" : \[[^\]]*\]', '"linear-gradient" : [\n                  "srgb:0.00000,0.00000,0.00000,1.00000",\n                  "srgb:0.06000,0.06000,0.06000,1.00000"\n                ]', text)
    text = re.sub(r'"automatic-gradient" : "[^"]*"', '"automatic-gradient" : "srgb:0.00000,0.00000,0.00000,1.00000"', text)
    js.write_text(text, encoding="utf-8")
    print("[litvin_patch] installed Litvin icon into Telegram.icon")


def patch_telegramui_build(text, label):
    return insert_after(
        text,
        r"swift_library\(\n\s*name = \"TelegramUI\",[\s\S]*?^    deps = \[\n",
        '        "//submodules/LitvinFeatures/LitvinVoiceKit:LitvinVoiceKit",\n'
        '        "//submodules/LitvinFeatures/LitvinSettings:LitvinSettings",\n',
        label,
    )


def patch_tgvoip_build(text, label):
    return insert_after(
        text,
        r"objc_library\(\n\s*name = \"TgVoipWebrtc\",[\s\S]*?^    deps = \[\n",
        '        "//submodules/LitvinFeatures/LitvinVoiceKit:LitvinVoiceDsp",\n',
        label,
    )


def patch_open_plugin_file(text, label):
    return insert_after(
        text,
        r"^func openChatMessageImpl\(_ params: OpenChatMessageParams\) -> Bool \{\n",
        "    if litvinOpenPluginFileIfNeeded(params) {\n"
        "        return true\n"
        "    }\n",
        label,
    )


def patch_outgoing_plugins(text, label):
    text = add_import(text, "LitvinSettings", label)
    return insert_after(
        text,
        r"    func sendMessages\(_ messages: \[EnqueueMessage\], media: Bool = false, postpone: Bool = false, commit: Bool = false\) \{\n",
        "        let messages = litvinMapOutgoingTexts(messages, { LitvinPluginManager.shared.transformOutgoingText($0) })\n"
        "        if messages.isEmpty {\n"
        "            return\n"
        "        }\n",
        label,
    )


# ---------------------------------------------------------------------------
# Appearance: Litvin app icons and the Litvin theme colour.
# ---------------------------------------------------------------------------

LITVIN_ICONS = [
    ("BlueIcon", "Классика"),
    ("BlackIcon", "Белая"),
    ("New1", "Малиновая"),
    ("New2", "Неон"),
    ("BlueClassicIcon", "Золото"),
    ("BlackClassicIcon", "Океан"),
    ("BlueFilledIcon", "Изумруд"),
    ("BlackFilledIcon", "Закат"),
]


def install_alt_icons(root):
    src = Path(__file__).resolve().parent.parent / "branding" / "alt-icons"
    dst = root / "Telegram/Telegram-iOS"
    count = 0
    for f in src.rglob("*.png"):
        target = dst / f.relative_to(src)
        if target.parent.is_dir():
            target.write_bytes(f.read_bytes())
            count += 1
    print(f"[litvin_patch] installed {count} Litvin alternate icon images")


def patch_icon_list(text, label):
    if '"Классика"' in text or "litvinIcons" in text:
        return text
    match = re.search(r"                var icons = \[\n[\s\S]*?\n                return icons\n", text)
    if match is None:
        raise SystemExit(f"[litvin_patch] alternate icon list not found ({label})")
    lines = ["                // Litvin: our icons only, none of them is Premium-locked.", "                let litvinIcons: [PresentationAppIcon] = ["]
    for i, (name, _) in enumerate(LITVIN_ICONS):
        comma = "," if i < len(LITVIN_ICONS) - 1 else ""
        lines.append(f'                    PresentationAppIcon(name: "{name}", imageName: "{name}"){comma}')
    lines.append("                ]")
    lines.append("                return litvinIcons")
    return text[:match.start()] + "\n".join(lines) + "\n" + text[match.end():]


def patch_icon_names(text, label):
    mapping = {
        "Appearance_AppIconDefault\n": "Классика",
        "Appearance_AppIconDefaultX\n": "Белая",
        "Appearance_AppIconClassic\n": "Золото",
        "Appearance_AppIconClassicX\n": "Океан",
        "Appearance_AppIconFilled\n": "Изумруд",
        "Appearance_AppIconFilledX\n": "Закат",
        "Appearance_AppIconNew1\n": "Малиновая",
        "Appearance_AppIconNew2\n": "Неон",
    }
    for key, title in mapping.items():
        old = f"name = item.strings.{key}"
        new = f'name = "{title}"\n'
        if new in text:
            continue
        text = replace_once(text, old, new, label)
    return text


LITVIN_PRESETS = {
    "dayClassicColorPresets": '    // Litvin\n    PresentationThemeAccentColor(index: 120, baseColor: .preset, accentColor: 0xFFE0163A, bubbleColors: [0xFFFFE1E8, 0xFFEBDDFF], wallpaper: patternWallpaper(data: .variant2, colors: [0xff6b8a, 0xc35ad6, 0x7a5cff, 0xff4f7b], intensity: 50, rotation: nil)),\n\n',
    "dayColorPresets": '    PresentationThemeAccentColor(index: 120, baseColor: .preset, accentColor: 0xE0163A, bubbleColors: [0xE0163A, 0x6A1A8C], wallpaper: nil),\n',
    "nightColorPresets": '    PresentationThemeAccentColor(index: 120, baseColor: .preset, accentColor: 0xE0163A, bubbleColors: [0xE0163A, 0x6A1A8C], wallpaper: patternWallpaper(data: .variant2, colors: [0x3a0a1f, 0x4b1683, 0x1a0612, 0x6a1a3c], intensity: -40, rotation: nil)),\n',
}


def patch_theme_presets(text, label):
    if "index: 120" in text:
        return text
    for var, snippet in LITVIN_PRESETS.items():
        text = insert_after(text, rf"^var {var}: \[PresentationThemeAccentColor\] = \[\n", snippet, label)
    return text


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: litvin_patch.py <tg-ios-root>")
    root = Path(sys.argv[1])
    edit(root, f"{PEERINFO}/BUILD", patch_build)
    edit(root, "Telegram/BUILD", patch_app_display_name)
    install_icon_composer(root)
    install_alt_icons(root)
    edit(root, "submodules/TelegramUI/Sources/AppDelegate.swift", patch_icon_list)
    edit(root, "submodules/SettingsUI/Sources/Themes/ThemeSettingsAppIconItem.swift", patch_icon_names)
    edit(root, "submodules/SettingsUI/Sources/Themes/ThemeColorPresets.swift", patch_theme_presets)
    for strings in sorted(root.glob("Telegram/Telegram-iOS/*.lproj/InfoPlist.strings")):
        if "CFBundleDisplayName" in strings.read_text(encoding="utf-8"):
            edit(root, str(strings.relative_to(root)), patch_localized_display_name)
    edit(root, f"{PEERINFO}/Sources/PeerInfoScreen.swift", patch_section_enum)
    edit(root, f"{PEERINFO}/Sources/PeerInfoSettingsItems.swift", patch_settings_items)
    edit(root, f"{PEERINFO}/Sources/PeerInfoScreenSettingsActions.swift", patch_settings_actions)

    core = "submodules/TelegramCore/Sources"
    edit(root, f"{core}/Account/AccountManager.swift", patch_register_deleted_attribute)
    edit(root, f"{core}/State/AccountStateManagementUtils.swift", patch_remote_delete)
    edit(root, "submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode/Sources/StringForMessageTimestampStatus.swift", patch_deleted_status_text)
    edit(root, "submodules/TelegramUI/Components/Chat/ChatMessageItemView/Sources/ChatMessageItemView.swift", patch_deleted_alpha)

    edit(root, f"{core}/Utils/MessageUtils.swift", bypass_protection_checks(3))
    edit(root, f"{core}/Utils/PeerUtils.swift", bypass_protection_checks(2))
    edit(root, f"{core}/TelegramEngine/Data/PeersData.swift", bypass_protection_checks(3, region=r"public struct CopyProtectionEnabled: [\s\S]*?(?=public struct )"))
    edit(root, "submodules/TelegramUI/Sources/ChatHistoryListNode.swift", bypass_protection_checks(2))
    edit(root, "submodules/GalleryUI/Sources/GalleryController.swift", bypass_protection_checks(2))
    edit(root, "submodules/TelegramUI/Sources/StoreDownloadedMedia.swift", bypass_protection_checks(3))
    edit(root, "submodules/TelegramUI/Sources/ChatControllerContentData.swift", patch_content_data_protection)
    edit(root, f"{core}/PendingMessages/EnqueueMessage.swift", patch_forward_as_copy)
    edit(root, "submodules/UIKitRuntimeUtils/Source/UIKitRuntimeUtils/UIKitUtils.m", patch_layer_screenshots)
    edit(root, "submodules/ScreenCaptureDetection/Sources/ScreenCaptureDetection.swift", patch_screenshot_detection)

    edit(root, f"{core}/TelegramEngine/Messages/MarkMessageContentAsConsumedInteractively.swift", patch_view_once)

    edit(root, "submodules/RMIntro/Sources/platform/ios/RMIntroViewController.m", patch_intro_logo)
    edit(root, "submodules/TelegramUI/Sources/AppDelegate.swift", patch_privacy_cover)
    write_custom_logo_swift(root)

    state = f"{core}/State"
    edit(root, f"{state}/SynchronizePeerReadState.swift", chain(
        wrap_calls("network.request(Api.functions.channels.readHistory(", "litvinGhostRequest", 1),
        wrap_calls("network.request(Api.functions.messages.readHistory(", "litvinGhostRequest", 1),
        wrap_calls("network.request(Api.functions.messages.readEncryptedHistory(", "litvinGhostRequest", 1),
    ))
    edit(root, f"{core}/TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift",
         wrap_calls("network.request(Api.functions.messages.readDiscussion(", "litvinGhostRequest", 3))
    edit(root, f"{core}/TelegramEngine/Messages/ReplyThreadHistory.swift",
         wrap_calls("strongSelf.account.network.request(Api.functions.messages.readDiscussion(", "litvinGhostRequest", 1))
    edit(root, f"{state}/ManagedLocalInputActivities.swift", chain(
        wrap_calls("network.request(Api.functions.messages.setTyping(", "litvinGhostRequest", 1),
        wrap_calls("network.request(Api.functions.messages.setEncryptedTyping(", "litvinGhostRequest", 1),
    ))
    edit(root, f"{state}/ManagedSynchronizeConsumeMessageContentsOperations.swift", chain(
        wrap_calls("network.request(Api.functions.messages.readMessageContents(", "litvinGhostRequest", 1),
        wrap_calls("network.request(Api.functions.channels.readMessageContents(", "litvinGhostRequest", 1),
    ))
    edit(root, f"{state}/ManagedAccountPresence.swift", patch_ghost_presence)

    edit(root, f"{core}/TelegramEngine/Messages/AdMessages.swift", patch_anti_ads)
    edit(root, f"{state}/AccountStateManagementUtils.swift", patch_edit_history_core)
    edit(root, "submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift", patch_edit_history_menu)
    edit(root, "submodules/ChatListUI/Sources/ChatContextMenus.swift", patch_chat_list_menu)
    edit(root, "submodules/ChatListUI/BUILD", patch_chat_list_build)
    edit(root, "submodules/TelegramUI/Sources/ChatController.swift", patch_confetti)
    edit(root, "submodules/TelegramUI/Sources/ChatController.swift", patch_outgoing_plugins)
    edit(root, "submodules/TelegramUI/Sources/OpenChatMessage.swift", patch_open_plugin_file)
    edit(root, "submodules/TelegramUI/Components/Chat/ChatMessageInteractiveFileNode/Sources/ChatMessageInteractiveFileNode.swift", patch_local_transcription)
    edit(root, f"{core}/Account/Account.swift", patch_auto_reply)

    edit(root, "submodules/TelegramUI/Sources/ManagedAudioRecorder.swift", patch_voice_recorder)
    edit(root, "submodules/TelegramUI/BUILD", patch_telegramui_build)
    edit(root, "submodules/TgVoipWebrtc/BUILD", patch_tgvoip_build)
    tgcalls = "submodules/TgVoipWebrtc/tgcalls/tgcalls"
    for rel in ("v2/InstanceV2Impl.cpp", "v2/InstanceV2ReferenceImpl.cpp", "v2/InstanceV2CompatImpl.cpp", "v2wasm/CallCoreHost.cpp"):
        edit(root, f"{tgcalls}/{rel}", patch_call_voice)
    voice_header = add_cpp_include("utils/LitvinVoiceProcessing.h")
    edit(root, f"{tgcalls}/group/GroupInstanceCustomImpl.cpp", chain(
        voice_header,
        wrap_call_argument("builder.SetCapturePostProcessing(", "litvin::WrapWithVoiceChanger", 1),
        patch_group_call_fallback,
    ))
    edit(root, f"{tgcalls}/group/GroupInstanceReferenceImpl.cpp", chain(
        voice_header,
        wrap_call_argument("builder.SetCapturePostProcessing(", "litvin::WrapWithVoiceChanger", 1),
    ))
    edit(root, f"{tgcalls}/MediaManager.cpp", chain(
        voice_header,
        wrap_call_argument("builder.SetCapturePostProcessing(", "litvin::WrapWithVoiceChanger", 1),
    ))


if __name__ == "__main__":
    main()
