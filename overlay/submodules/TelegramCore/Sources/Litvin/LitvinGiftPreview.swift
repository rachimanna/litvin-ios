import Foundation
import Postbox
import SwiftSignalKit

public func litvinGiftPreviewEnabled(account: Int64) -> Bool {
    LitvinAppearance.state(account: account).giftPreviewEnabled ?? true
}

public func litvinGiftDate(_ gift: StarGift) -> Int32 {
    if case let .unique(gift) = gift {
        for attribute in gift.attributes {
            if case let .originalInfo(_, _, date, _, _) = attribute { return date }
        }
    }
    return 0
}

/// Private presentation copy. No ownership, payment or transfer RPC is issued.
public func litvinGiftPresentation(account: Int64, sender: EnginePeer.Id, peer: EnginePeer.Id, gift: StarGift, date: Int32) -> StarGift {
    let presentationGift: StarGift
    switch gift {
    case .generic: presentationGift = gift
    case let .unique(gift):
        var attributes = gift.attributes.filter { if case .originalInfo = $0 { return false }; return true }
        attributes.append(.originalInfo(senderPeerId: sender, recipientPeerId: peer, date: date, text: nil, entities: nil))
        let price = max(0, min(LitvinAppearance.maximumStars, LitvinAppearance.state(account: account).giftPreviewPrice ?? 1000))
        presentationGift = .unique(StarGift.UniqueGift(
            id: gift.id, giftId: gift.giftId, title: gift.title, number: gift.number, slug: gift.slug,
            owner: .peerId(peer), attributes: attributes, availability: gift.availability,
            giftAddress: nil, resellAmounts: price > 0 ? [CurrencyAmount(amount: StarsAmount(value: price, nanos: 0), currency: .stars)] : nil,
            resellForTonOnly: false, releasedBy: gift.releasedBy, valueAmount: nil, valueCurrency: nil,
            valueUsdAmount: nil, flags: gift.flags, themePeerId: gift.themePeerId, peerColor: gift.peerColor,
            hostPeerId: nil, minOfferStars: nil, craftChancePermille: gift.craftChancePermille))
    }
    return presentationGift
}

@discardableResult public func litvinSaveGiftPreview(account: Int64, sender: EnginePeer.Id, peer: EnginePeer.Id, gift: StarGift) -> Bool {
    let presentationGift = litvinGiftPresentation(account: account, sender: sender, peer: peer, gift: gift, date: Int32(Date().timeIntervalSince1970))
    guard let data = try? JSONEncoder().encode(presentationGift) else { return false }
    return LitvinAppearance.update(account: account) { $0.gifts[String(peer.toInt64()), default: [:]][litvinGiftKey(presentationGift)] = data }
}

public final class LitvinGiftPreviewMessageAttribute: MessageAttribute {
    public init() {}
    public init(decoder: PostboxDecoder) {}
    public func encode(_ encoder: PostboxEncoder) {}
}

public func litvinIsGiftPreviewMessage(_ message: EngineMessage) -> Bool {
    message.id.namespace == Namespaces.Message.Local && message.attributes.contains(where: { $0 is LitvinGiftPreviewMessageAttribute })
}

/// Store a native gift service card locally, without enqueueing an outgoing message.
public func litvinSendGiftPreview(account: Account, peerId: EnginePeer.Id, gift: StarGift) -> Signal<Bool, NoError> {
    return account.postbox.transaction { transaction in
        guard transaction.getPeer(peerId) != nil else { return false }
        let timestamp = Int32(Date().timeIntervalSince1970)
        let preview = litvinGiftPresentation(account: account.peerId.toInt64(), sender: account.peerId, peer: peerId, gift: gift, date: timestamp)
        guard let data = try? JSONEncoder().encode(preview),
              LitvinAppearance.update(account: account.peerId.toInt64(), { $0.gifts[String(peerId.toInt64()), default: [:]][litvinGiftKey(preview)] = data }) else { return false }
        let action: TelegramMediaActionType
        switch preview {
        case .unique:
            action = .starGiftUnique(gift: preview, isUpgrade: false, isTransferred: false, savedToProfile: true, canExportDate: nil, transferStars: nil, isRefunded: false, isPrepaidUpgrade: false, peerId: peerId, senderId: account.peerId, savedId: nil, resaleAmount: nil, canTransferDate: nil, canResaleDate: nil, dropOriginalDetailsStars: nil, assigned: false, fromOffer: false, canCraftAt: nil, isCrafted: false, text: nil, entities: nil, nameHidden: false)
        case .generic:
            action = .starGift(gift: preview, convertStars: nil, text: nil, entities: nil, nameHidden: false, savedToProfile: true, converted: false, upgraded: false, canUpgrade: false, upgradeStars: nil, isRefunded: false, isPrepaidUpgrade: false, upgradeMessageId: nil, peerId: peerId, senderId: account.peerId, savedId: nil, prepaidUpgradeHash: nil, giftMessageId: nil, upgradeSeparate: false, isAuctionAcquired: false, toPeerId: peerId, number: nil)
        }
        let message = StoreMessage(peerId: peerId, namespace: Namespaces.Message.Local, customStableId: nil, globallyUniqueId: Int64.random(in: Int64.min...Int64.max), groupingKey: nil, threadId: nil, timestamp: timestamp, flags: [], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: account.peerId, text: "", attributes: [LitvinGiftPreviewMessageAttribute()], media: [TelegramMediaAction(action: action)])
        let _ = transaction.addMessages([message], location: .Random)
        updatePeerChatInclusionWithMinTimestamp(transaction: transaction, id: peerId, minTimestamp: timestamp, forceRootGroupIfNotExists: true)
        return true
    }
}
