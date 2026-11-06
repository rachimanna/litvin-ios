import Foundation
import Postbox
import LitvinCore

private func litvinPeerTitle(_ peer: Peer?) -> String {
    switch peer {
    case let peer as TelegramUser: return [peer.firstName, peer.lastName].compactMap { $0 }.joined(separator: " ")
    case let peer as TelegramGroup: return peer.title
    case let peer as TelegramChannel: return peer.title
    default: return ""
    }
}

public func litvinCaptureMessage(accountPeerId: PeerId, message: Message, beforeEdit: Bool = false) {
    // Secret chat content stays exclusively in Telegram's secret-chat storage.
    guard message.id.namespace == Namespaces.Message.Cloud else { return }
    let peer = message.peers[message.id.peerId]
    let record = LitvinMessageRecord(account: accountPeerId.toInt64(), peer: message.id.peerId.toInt64(), namespace: message.id.namespace, message: message.id.id, author: message.author?.id.toInt64(), timestamp: message.timestamp, text: message.text, outgoing: !message.flags.contains(.Incoming), channel: peer is TelegramChannel, peerTitle: litvinPeerTitle(peer))
    let store = LitvinArchive.forAccount(accountPeerId.toInt64())
    if beforeEdit { store.beforeEdit(record) } else { store.observe(record) }
}

func litvinCaptureStoreMessage(accountPeerId: PeerId, transaction: Transaction, message: StoreMessage) {
    guard case let .Id(id) = message.id, id.namespace == Namespaces.Message.Cloud else { return }
    let peer = transaction.getPeer(id.peerId)
    let record = LitvinMessageRecord(account: accountPeerId.toInt64(), peer: id.peerId.toInt64(), namespace: id.namespace, message: id.id, author: message.authorId?.toInt64(), timestamp: message.timestamp, text: message.text, outgoing: !message.flags.contains(.Incoming), channel: peer is TelegramChannel, peerTitle: litvinPeerTitle(peer))
    LitvinArchive.forAccount(accountPeerId.toInt64()).observe(record)
}
