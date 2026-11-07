import Foundation
import Postbox
import TelegramCore
import AccountContext
import ChatHistoryEntry
import TelegramPresentationData
import LitvinCore

func litvinInsertDeletedEntries(_ original: [ChatHistoryEntry], context: AccountContext, location: ChatLocation, subject: ChatControllerSubject?, view: MessageHistoryView, presentationData: ChatPresentationData, chatPeer: Peer?) -> [ChatHistoryEntry] {
    guard LitvinPolicy.options.saveDeleted, subject == nil, case let .peer(peerId) = location,
          peerId.namespace != Namespaces.Peer.SecretChat, view.tag == nil, !view.isLoading else { return original }
    if let channel = chatPeer as? TelegramChannel, channel.isForumOrMonoForum { return original }
    let account = context.account.peerId.toInt64()
    guard !LitvinProtection.shouldHide(account: account, peer: peerId.toInt64()) else { return original }
    let vault = LitvinPrivateArchive.forAccount(account)
    // Encrypted histories stay inside their lock-aware archive controller.
    guard !vault.isProtected(peerId.toInt64()) else { return original }
    let state = LitvinArchive.forAccount(account).snapshot()
    let existingIds = Set(view.entries.map { $0.message.id })
    let lower = view.holeEarlier ? view.entries.first?.message.timestamp : nil
    let upper = view.holeLater ? view.entries.last?.message.timestamp : nil
    // Stable identities live in a reserved presentation range and never become
    // outgoing messages. Resolve collisions with loaded messages deterministically.
    var stableIds = Set(view.entries.map { $0.message.stableId })
    var result = original
    let records = state.messages.values.filter {
        $0.peer == peerId.toInt64() && $0.namespace == Namespaces.Message.Cloud && $0.deleted && $0.message > 0
            && (lower == nil || $0.timestamp >= lower!) && (upper == nil || $0.timestamp <= upper!)
    }.sorted { $0.message < $1.message }
    for record in records.prefix(500) {
        let originalId = MessageId(peerId: peerId, namespace: record.namespace, id: record.message)
        guard !existingIds.contains(originalId) else { continue }
        var stableId = UInt32.max &- 10_000 &- UInt32(bitPattern: record.message)
        while stableIds.contains(stableId) { stableId &-= 1 }
        stableIds.insert(stableId)
        var peers = SimpleDictionary<PeerId, Peer>()
        if let chatPeer { peers[chatPeer.id] = chatPeer }
        for entry in view.entries { for (id, peer) in entry.message.peers { peers[id] = peer } }
        let authorId = record.author.map(PeerId.init)
        let author = authorId.flatMap { peers[$0] }
        let message = Message(stableId: stableId, stableVersion: 1,
            id: MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: -max(1, record.message)),
            globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: record.timestamp,
            flags: record.outgoing ? [] : [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [],
            forwardInfo: nil, author: author, text: "Удалено\n" + (record.text.isEmpty ? "Сообщение с медиа" : record.text),
            attributes: [LitvinDeletedMessageAttribute()], media: [], peers: peers,
            associatedMessages: SimpleDictionary<MessageId, Message>(), associatedMessageIds: [], associatedMedia: [:],
            associatedThreadInfo: nil, associatedStories: [:])
        result.append(.MessageEntry(message, presentationData, true, nil, .none, ChatMessageEntryAttributes()))
    }
    result.sort()
    return result
}
