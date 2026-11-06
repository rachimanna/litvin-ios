import Foundation
import Postbox
import SwiftSignalKit

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

    // Ghost mode is OFF by default, so it is stored as "litvin.on.ghostMode".
    public static let ghostModeKey = "litvin.on.ghostMode"

    // No read receipts, no typing, no online status.
    public static var ghostMode: Bool {
        return UserDefaults.standard.bool(forKey: ghostModeKey)
    }

    public static func setGhostMode(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: ghostModeKey)
    }
}

// Voice changer settings, shared by the voice-message recorder (Swift) and the
// call audio pipeline (C++ reads the same keys through CFPreferences).
public struct LitvinVoiceSettings: Equatable {
    public enum Preset: Int, CaseIterable {
        case off = 0
        case angry = 1
        case girl = 2
        case child = 3
        case pixel = 4
        case robot = 5
        case vocal = 6

        public var title: String {
            switch self {
            case .off: return "Выключено"
            case .angry: return "Злой"
            case .girl: return "Девушка"
            case .child: return "Ребёнок"
            case .pixel: return "Пиксель"
            case .robot: return "Робот"
            case .vocal: return "Вокал"
            }
        }
    }

    public var preset: Preset
    // Extra pitch on top of the preset, in semitones (-12 ... 12).
    public var pitch: Double
    // How much of the effect is heard: 0 = original voice, 1 = only the effect.
    public var strength: Double
    // Output volume, 0 ... 2 (1 = unchanged).
    public var volume: Double
    // Added echo / reverb, 0 ... 1.
    public var echo: Double
    public var voiceMessages: Bool
    public var calls: Bool

    public static let presetKey = "litvin.voice.preset"
    public static let pitchKey = "litvin.voice.pitch"
    public static let strengthKey = "litvin.voice.strength"
    public static let volumeKey = "litvin.voice.volume"
    public static let echoKey = "litvin.voice.echo"
    public static let voiceMessagesKey = "litvin.voice.messages"
    public static let callsKey = "litvin.voice.calls"

    private static func double(_ key: String, _ defaultValue: Double) -> Double {
        if let value = UserDefaults.standard.object(forKey: key) as? NSNumber {
            return value.doubleValue
        }
        return defaultValue
    }

    private static func bool(_ key: String, _ defaultValue: Bool) -> Bool {
        if let value = UserDefaults.standard.object(forKey: key) as? NSNumber {
            return value.boolValue
        }
        return defaultValue
    }

    public static var current: LitvinVoiceSettings {
        let defaults = UserDefaults.standard
        return LitvinVoiceSettings(
            preset: Preset(rawValue: defaults.integer(forKey: presetKey)) ?? .off,
            pitch: double(pitchKey, 0.0),
            strength: double(strengthKey, 1.0),
            volume: double(volumeKey, 1.0),
            echo: double(echoKey, 0.0),
            voiceMessages: bool(voiceMessagesKey, true),
            calls: bool(callsKey, true)
        )
    }

    public func save() {
        let defaults = UserDefaults.standard
        defaults.set(self.preset.rawValue, forKey: LitvinVoiceSettings.presetKey)
        defaults.set(self.pitch, forKey: LitvinVoiceSettings.pitchKey)
        defaults.set(self.strength, forKey: LitvinVoiceSettings.strengthKey)
        defaults.set(self.volume, forKey: LitvinVoiceSettings.volumeKey)
        defaults.set(self.echo, forKey: LitvinVoiceSettings.echoKey)
        defaults.set(self.voiceMessages, forKey: LitvinVoiceSettings.voiceMessagesKey)
        defaults.set(self.calls, forKey: LitvinVoiceSettings.callsKey)
    }

    // Anything to do at all (a preset, or echo / pitch / volume changed by hand).
    public var isActive: Bool {
        return self.preset != .off || abs(self.pitch) > 0.01 || self.echo > 0.01 || abs(self.volume - 1.0) > 0.01
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

// Ghost mode: drop a request that would reveal activity (read receipts,
// typing, "listened"). Completes immediately so callers carry on as if sent.
func litvinGhostRequest<T, E>(_ request: @autoclosure () -> Signal<T, E>) -> Signal<T, E> {
    if LitvinFlags.ghostMode {
        return .complete()
    }
    return request()
}
