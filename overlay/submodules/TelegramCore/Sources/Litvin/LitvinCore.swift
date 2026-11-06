import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi

// Litvin runtime switches. Stored as "litvin.off.<key>" so every feature is ON
// by default (missing key == enabled). Read from TelegramCore, TelegramUI and
// ObjC (UIKitRuntimeUtils reads the same NSUserDefaults key directly).
public enum LitvinFlags {
    public static let keepDeletedKey = "keepDeleted"
    public static let bypassProtectionKey = "bypassProtection"
    public static let unlimitedViewOnceKey = "unlimitedViewOnce"
    public static let topBadgeKey = "topBadge"
    public static let antiAdsKey = "antiAds"
    public static let editHistoryKey = "editHistory"
    public static let confettiKey = "confetti"
    public static let localTranscriptionKey = "localTranscription"

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

    // No sponsored messages in channels.
    public static var antiAds: Bool {
        return isEnabled(antiAdsKey)
    }

    // Keep previous versions of edited messages.
    public static var editHistory: Bool {
        return isEnabled(editHistoryKey)
    }

    // Confetti on the screen when you send "С днём рождения", "🎉" etc.
    public static var confetti: Bool {
        return isEnabled(confettiKey)
    }

    // Voice / video message -> text on the device, without Premium.
    public static var localTranscription: Bool {
        return isEnabled(localTranscriptionKey)
    }

    // Auto-reply in private chats (off by default).
    public static let autoReplyKey = "litvin.on.autoReply"
    public static let autoReplyTextKey = "litvin.autoReply.text"
    public static let defaultAutoReplyText = "Сейчас не могу ответить, напишу позже."

    public static var autoReply: Bool {
        return UserDefaults.standard.bool(forKey: autoReplyKey)
    }

    public static func setAutoReply(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: autoReplyKey)
    }

    public static var autoReplyText: String {
        if let text = UserDefaults.standard.string(forKey: autoReplyTextKey), !text.isEmpty {
            return text
        }
        return defaultAutoReplyText
    }

    public static func setAutoReplyText(_ text: String) {
        UserDefaults.standard.set(text, forKey: autoReplyTextKey)
    }

    // "LITVIN" pill under the Dynamic Island, visible on screenshots.
    public static var topBadge: Bool {
        return isEnabled(topBadgeKey)
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

// Voice changer settings: one switch for everything — voice messages, 1:1 calls
// and group calls. The call audio pipeline (C++) reads the same keys through
// CFPreferences.
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

    public static let presetKey = "litvin.voice.preset"
    public static let pitchKey = "litvin.voice.pitch"
    public static let strengthKey = "litvin.voice.strength"
    public static let volumeKey = "litvin.voice.volume"
    public static let echoKey = "litvin.voice.echo"

    private static func double(_ key: String, _ defaultValue: Double) -> Double {
        if let value = UserDefaults.standard.object(forKey: key) as? NSNumber {
            return value.doubleValue
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
            echo: double(echoKey, 0.0)
        )
    }

    public func save() {
        let defaults = UserDefaults.standard
        defaults.set(self.preset.rawValue, forKey: LitvinVoiceSettings.presetKey)
        defaults.set(self.pitch, forKey: LitvinVoiceSettings.pitchKey)
        defaults.set(self.strength, forKey: LitvinVoiceSettings.strengthKey)
        defaults.set(self.volume, forKey: LitvinVoiceSettings.volumeKey)
        defaults.set(self.echo, forKey: LitvinVoiceSettings.echoKey)
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


// ---------------------------------------------------------------------------
// Edit history
// ---------------------------------------------------------------------------

public struct LitvinEditVersion: Equatable {
    public let date: Int32
    public let text: String
}

public class LitvinEditHistoryMessageAttribute: MessageAttribute {
    public let versions: [LitvinEditVersion]

    public init(versions: [LitvinEditVersion]) {
        self.versions = versions
    }

    required public init(decoder: PostboxDecoder) {
        let dates = decoder.decodeInt32ArrayForKey("d")
        let texts = decoder.decodeStringArrayForKey("t")
        var versions: [LitvinEditVersion] = []
        for i in 0 ..< min(dates.count, texts.count) {
            versions.append(LitvinEditVersion(date: dates[i], text: texts[i]))
        }
        self.versions = versions
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32Array(self.versions.map { $0.date }, forKey: "d")
        encoder.encodeStringArray(self.versions.map { $0.text }, forKey: "t")
    }
}

public extension Message {
    var litvinEditHistory: LitvinEditHistoryMessageAttribute? {
        return self.attributes.first(where: { $0 is LitvinEditHistoryMessageAttribute }) as? LitvinEditHistoryMessageAttribute
    }
}

// Called while applying a remote edit: remembers the previous text and keeps
// Litvin's local attributes, which the server copy of the message lacks.
func litvinApplyEditHistory(previous: Message, newText: String, attributes: inout [MessageAttribute]) {
    if let deleted = previous.attributes.first(where: { $0 is LitvinDeletedMessageAttribute }), !attributes.contains(where: { $0 is LitvinDeletedMessageAttribute }) {
        attributes.append(deleted)
    }
    var versions = previous.litvinEditHistory?.versions ?? []
    if LitvinFlags.editHistory && previous.text != newText && !previous.text.isEmpty {
        var date = previous.timestamp
        if let edited = previous.attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute {
            date = edited.date
        }
        versions.append(LitvinEditVersion(date: date, text: previous.text))
        if versions.count > 50 {
            versions.removeFirst(versions.count - 50)
        }
    }
    attributes.removeAll(where: { $0 is LitvinEditHistoryMessageAttribute })
    if !versions.isEmpty {
        attributes.append(LitvinEditHistoryMessageAttribute(versions: versions))
    }
}

public func litvinEditHistoryText(_ attribute: LitvinEditHistoryMessageAttribute, current: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "d MMM, HH:mm"
    var lines: [String] = []
    for version in attribute.versions {
        let date = formatter.string(from: Date(timeIntervalSince1970: Double(version.date)))
        lines.append("\(date)\n\(version.text)")
    }
    lines.append("Сейчас\n\(current)")
    return lines.joined(separator: "\n\n")
}

// ---------------------------------------------------------------------------
// Confetti keywords
// ---------------------------------------------------------------------------

private let litvinConfettiPhrases: [String] = [
    "с днём рождения", "с днем рождения", "поздравляю", "поздравляем",
    "с новым годом", "с праздником", "happy birthday", "congratulations",
    "🎉", "🥳", "🎊", "🎂"
]

// Short words only count as separate words ("ура", but not "дура").
private let litvinConfettiWords: Set<String> = ["ура", "congrats"]

public func litvinShouldPlayConfetti(_ messages: [EnqueueMessage]) -> Bool {
    if !LitvinFlags.confetti {
        return false
    }
    for message in messages {
        if case let .message(text, _, _, _, _, _, _, _, _, _) = message {
            let lowercased = text.lowercased()
            if litvinConfettiPhrases.contains(where: { lowercased.contains($0) }) {
                return true
            }
            let words = lowercased.components(separatedBy: CharacterSet.letters.inverted)
            if words.contains(where: { litvinConfettiWords.contains($0) }) {
                return true
            }
        }
    }
    return false
}

// ---------------------------------------------------------------------------
// Ghost mode: "read for the other side" on demand
// ---------------------------------------------------------------------------

public func litvinForceReadHistory(account: Account, peerId: PeerId) -> Signal<Never, NoError> {
    let postbox = account.postbox
    let network = account.network
    let stateManager = account.stateManager
    return postbox.transaction { transaction -> (Api.InputPeer?, Int32?) in
        let inputPeer = transaction.getPeer(peerId).flatMap(apiInputPeer)
        let topId = transaction.getTopPeerMessageId(peerId: peerId, namespace: Namespaces.Message.Cloud)
        return (inputPeer, topId?.id)
    }
    |> mapToSignal { inputPeer, maxId -> Signal<Never, NoError> in
        guard let inputPeer, let maxId else {
            return .complete()
        }
        if case let .inputPeerChannel(channelData) = inputPeer {
            return network.request(Api.functions.channels.readHistory(channel: .inputChannel(.init(channelId: channelData.channelId, accessHash: channelData.accessHash)), maxId: maxId))
            |> `catch` { _ -> Signal<Api.Bool, NoError> in
                return .complete()
            }
            |> ignoreValues
        } else {
            return network.request(Api.functions.messages.readHistory(peer: inputPeer, maxId: maxId))
            |> map(Optional.init)
            |> `catch` { _ -> Signal<Api.messages.AffectedMessages?, NoError> in
                return .single(nil)
            }
            |> mapToSignal { result -> Signal<Never, NoError> in
                if let result {
                    switch result {
                    case let .affectedMessages(affectedMessagesData):
                        stateManager.addUpdateGroups([.updatePts(pts: affectedMessagesData.pts, ptsCount: affectedMessagesData.ptsCount)])
                    }
                }
                return .complete()
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Auto-reply (private chats, while the app is running)
// ---------------------------------------------------------------------------

func litvinManagedAutoReply(account: Account) -> Signal<Void, NoError> {
    let accountPeerId = account.peerId
    var lastReplyByPeer: [PeerId: Double] = [:]
    let cooldown: Double = 30.0 * 60.0
    return account.stateManager.notificationMessages
    |> mapToSignal { [weak account] batches -> Signal<Void, NoError> in
        guard let account, LitvinFlags.autoReply else {
            return .complete()
        }
        let now = CFAbsoluteTimeGetCurrent()
        var signals: [Signal<[MessageId?], NoError>] = []
        for (messages, _, _, _) in batches {
            for message in messages {
                let peerId = message.id.peerId
                if peerId.namespace != Namespaces.Peer.CloudUser || peerId == accountPeerId {
                    continue
                }
                if !message.flags.contains(.Incoming) || message.id.namespace != Namespaces.Message.Cloud {
                    continue
                }
                if message.media.contains(where: { $0 is TelegramMediaAction }) {
                    continue
                }
                if let user = message.peers[peerId] as? TelegramUser, user.botInfo != nil || user.flags.contains(.isSupport) {
                    continue
                }
                if let last = lastReplyByPeer[peerId], now - last < cooldown {
                    continue
                }
                lastReplyByPeer[peerId] = now
                signals.append(enqueueMessages(account: account, peerId: peerId, messages: [.message(text: LitvinFlags.autoReplyText, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])]))
            }
        }
        if signals.isEmpty {
            return .complete()
        }
        return combineLatest(signals)
        |> map { _ -> Void in
            return Void()
        }
    }
}
