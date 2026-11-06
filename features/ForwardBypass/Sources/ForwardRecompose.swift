import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

/// Recompose a copy-protected message as a fresh outgoing message so it can leave
/// the chat without using server-side forward (which the server refuses for noforwards peers).
public enum ForwardRecompose {
    public static func build(from message: Message, toPeerId: PeerId) -> EnqueueMessage {
        let text = message.text
        var attributes: [MessageAttribute] = []
        for attr in message.attributes {
            if attr is TextEntitiesMessageAttribute {
                attributes.append(attr)
            }
        }

        var mediaRef: AnyMediaReference?
        if let media = message.media.first {
            mediaRef = .standalone(media: media)
        }

        return .message(
            text: text,
            attributes: attributes,
            inlineStickers: [:],
            mediaReference: mediaRef,
            threadId: nil,
            replyToMessageId: nil,
            replyToStoryId: nil,
            localGroupingKey: nil,
            correlationId: nil,
            bubbleUpEmojiOrStickersets: []
        )
    }
}
