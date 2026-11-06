import Foundation
import Postbox

// Litvin runtime switches. Stored as "litvin.off.<key>" so every feature is ON
// by default (missing key == enabled). Read from TelegramCore, TelegramUI and
// ObjC (UIKitRuntimeUtils reads the same NSUserDefaults key directly).
public enum LitvinFlags {
    public static let keepDeletedKey = "keepDeleted"
    public static let bypassProtectionKey = "bypassProtection"
    public static let unlimitedViewOnceKey = "unlimitedViewOnce"

    public static func isEnabled(_ key: String) -> Bool {
        return !UserDefaults.standard.bool(forKey: "litvin.off." + key)
    }

    public static func setEnabled(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(!value, forKey: "litvin.off." + key)
    }

    // Keep messages the other side deleted, mark them as deleted in the chat.
    public static var keepDeleted: Bool {
        return isEnabled(keepDeletedKey)
    }

    // Ignore "restrict saving content": copy, forward, save, screenshots.
    public static var bypassProtection: Bool {
        return isEnabled(bypassProtectionKey)
    }

    // View-once / self-destruct media can be opened any number of times.
    public static var unlimitedViewOnce: Bool {
        return isEnabled(unlimitedViewOnceKey)
    }
}

// Marker stored on a message that was deleted remotely but kept locally.
public class LitvinDeletedMessageAttribute: MessageAttribute {
    public let date: Int32

    public init(date: Int32) {
        self.date = date
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
    }
}

public extension Message {
    var litvinIsDeleted: Bool {
        return self.attributes.contains(where: { $0 is LitvinDeletedMessageAttribute })
    }
}

private func litvinShouldKeepDeleted(_ message: Message) -> Bool {
    if message.id.namespace != Namespaces.Message.Cloud {
        return false
    }
    let peerNamespace = message.id.peerId.namespace
    if peerNamespace != Namespaces.Peer.CloudUser && peerNamespace != Namespaces.Peer.CloudGroup && peerNamespace != Namespaces.Peer.CloudChannel {
        return false
    }
    if message.media.contains(where: { $0 is TelegramMediaAction }) {
        return false
    }
    return true
}

private func litvinMarkDeleted(transaction: Transaction, message: Message) {
    if message.litvinIsDeleted {
        return
    }
    let timestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
    transaction.updateMessage(message.id, update: { currentMessage in
        var attributes = currentMessage.attributes
        attributes.append(LitvinDeletedMessageAttribute(date: timestamp))
        return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
    })
}

// Called from the remote-delete update path: messages we keep are marked and
// dropped from the list that is actually removed from Postbox.
func litvinFilterDeletedMessageIds(transaction: Transaction, ids: [MessageId]) -> [MessageId] {
    if !LitvinFlags.keepDeleted {
        return ids
    }
    var result: [MessageId] = []
    for id in ids {
        if let message = transaction.getMessage(id), litvinShouldKeepDeleted(message) {
            litvinMarkDeleted(transaction: transaction, message: message)
        } else {
            result.append(id)
        }
    }
    return result
}

func litvinFilterDeletedGlobalIds(transaction: Transaction, ids: [Int32]) -> [Int32] {
    if !LitvinFlags.keepDeleted {
        return ids
    }
    var result: [Int32] = []
    for globalId in ids {
        var kept = false
        for id in transaction.messageIdsForGlobalIds([globalId]) {
            if let message = transaction.getMessage(id), litvinShouldKeepDeleted(message) {
                litvinMarkDeleted(transaction: transaction, message: message)
                kept = true
            }
        }
        if !kept {
            result.append(globalId)
        }
    }
    return result
}

// Protection as the server sees it (unaffected by the bypass), used to decide
// whether a forward must be re-sent as a copy.
func litvinIsRawCopyProtected(transaction: Transaction, message: Message) -> Bool {
    if message.flags.contains(.CopyProtected) {
        return true
    }
    if let peer = transaction.getPeer(message.id.peerId) {
        if let group = peer as? TelegramGroup, group.flags.contains(.copyProtectionEnabled) {
            return true
        }
        if let channel = peer as? TelegramChannel, channel.flags.contains(.copyProtectionEnabled) {
            return true
        }
    }
    if let cachedUserData = transaction.getPeerCachedData(peerId: message.id.peerId) as? CachedUserData {
        if cachedUserData.flags.contains(.copyProtectionEnabled) || cachedUserData.flags.contains(.myCopyProtectionEnabled) {
            return true
        }
    }
    return false
}
