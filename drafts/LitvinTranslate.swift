import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext

// Translate-on-send: in a chosen chat every text you send is translated into
// the chat's language by Telegram's own translation (free, no Premium).

public enum LitvinTranslate {
    private static let key = "litvin.translate.peers"

    /// Set while translated messages are being sent, so they are not
    /// translated or passed through plugins a second time.
    public static var isResending = false

    public static let languages: [(code: String, title: String)] = [
        ("en", "🇬🇧 English"),
        ("uk", "🇺🇦 Українська"),
        ("ru", "🇷🇺 Русский"),
        ("de", "🇩🇪 Deutsch"),
        ("es", "🇪🇸 Español"),
        ("fr", "🇫🇷 Français"),
        ("it", "🇮🇹 Italiano"),
        ("pl", "🇵🇱 Polski"),
        ("pt", "🇵🇹 Português"),
        ("tr", "🇹🇷 Türkçe"),
        ("kk", "🇰🇿 Қазақша"),
        ("uz", "🇺🇿 Oʻzbekcha"),
        ("zh", "🇨🇳 中文"),
        ("ja", "🇯🇵 日本語"),
        ("ko", "🇰🇷 한국어"),
        ("ar", "🇸🇦 العربية"),
    ]

    private static var map: [String: String] {
        return UserDefaults.standard.dictionary(forKey: self.key) as? [String: String] ?? [:]
    }

    public static var chatCount: Int {
        return self.map.count
    }

    public static func language(for peerId: EnginePeer.Id) -> String? {
        return self.map["\(peerId.toInt64())"]
    }

    public static func title(for code: String) -> String {
        return self.languages.first(where: { $0.code == code })?.title ?? code
    }

    public static func setLanguage(_ code: String?, for peerId: EnginePeer.Id) {
        var map = self.map
        map["\(peerId.toInt64())"] = code
        UserDefaults.standard.set(map, forKey: self.key)
    }
}

/// Language picker for one chat (chat list → long press → "Переводить мои сообщения").
public func litvinTranslateLanguageSheet(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let controller = ActionSheetController(theme: ActionSheetControllerTheme(presentationData: presentationData))
    let dismiss: () -> Void = { [weak controller] in
        controller?.dismissAnimated()
    }
    let current = LitvinTranslate.language(for: peerId)
    var items: [ActionSheetItem] = [
        ActionSheetTextItem(title: "Всё, что ты отправишь в этот чат, будет переведено на выбранный язык.")
    ]
    for language in LitvinTranslate.languages {
        let title = language.code == current ? "✓ " + language.title : language.title
        items.append(ActionSheetButtonItem(title: title, color: .accent, action: {
            dismiss()
            LitvinTranslate.setLanguage(language.code, for: peerId)
        }))
    }
    if current != nil {
        items.append(ActionSheetButtonItem(title: "Не переводить", color: .destructive, action: {
            dismiss()
            LitvinTranslate.setLanguage(nil, for: peerId)
        }))
    }
    controller.setItemGroups([
        ActionSheetItemGroup(items: items),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: {
                dismiss()
            })
        ])
    ])
    return controller
}

/// Called at the start of ChatController.sendMessages. Returns true when the
/// messages were taken over: they are sent again through `send` once translated.
public func litvinTranslateOutgoing(context: AccountContext, peerId: EnginePeer.Id?, messages: [EnqueueMessage], send: @escaping ([EnqueueMessage]) -> Void) -> Bool {
    guard !LitvinTranslate.isResending, let peerId, let language = LitvinTranslate.language(for: peerId) else {
        return false
    }
    var signals: [Signal<(Int, String, [MessageTextEntity])?, NoError>] = []
    for (index, message) in messages.enumerated() {
        guard case let .message(text, attributes, _, _, _, _, _, _, _, _) = message else {
            continue
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("/") {
            continue
        }
        var entities: [MessageTextEntity] = []
        for attribute in attributes {
            if let attribute = attribute as? TextEntitiesMessageAttribute {
                entities = attribute.entities
            }
        }
        signals.append(context.engine.messages.translate(text: text, toLang: language, entities: entities)
        |> map { result -> (Int, String, [MessageTextEntity])? in
            guard let result else {
                return nil
            }
            return (index, result.0, result.1)
        }
        |> `catch` { _ -> Signal<(Int, String, [MessageTextEntity])?, NoError> in
            return .single(nil)
        })
    }
    if signals.isEmpty {
        return false
    }
    let _ = (combineLatest(signals)
    |> take(1)
    |> timeout(8.0, queue: Queue.mainQueue(), alternate: .single([]))
    |> deliverOnMainQueue).startStandalone(next: { results in
        var updated = messages
        for case let (index, text, entities)? in results {
            guard case let .message(_, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = updated[index] else {
                continue
            }
            var updatedAttributes = attributes.filter { !($0 is TextEntitiesMessageAttribute) }
            if !entities.isEmpty {
                updatedAttributes.append(TextEntitiesMessageAttribute(entities: entities))
            }
            updated[index] = .message(text: text, attributes: updatedAttributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
        }
        LitvinTranslate.isResending = true
        send(updated)
        LitvinTranslate.isResending = false
    })
    return true
}
