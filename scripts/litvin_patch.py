#!/usr/bin/env python3
"""
Anchor-based source edits for Telegram-iOS. Each edit inserts a snippet after
a regex anchor, is idempotent, and fails loudly if the anchor is missing.

Usage: python3 litvin_patch.py <tg-ios-root>
"""
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
        "    items[.litvin]!.append(PeerInfoScreenDisclosureItem(id: 0, text: \"Litvin\", icon: PresentationResourcesSettings.proxy, action: {\n"
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
        "    declareEncodable(LitvinDeletedMessageAttribute.self, f: { LitvinDeletedMessageAttribute(decoder: $0) })\n",
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


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: litvin_patch.py <tg-ios-root>")
    root = Path(sys.argv[1])
    edit(root, f"{PEERINFO}/BUILD", patch_build)
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


if __name__ == "__main__":
    main()
