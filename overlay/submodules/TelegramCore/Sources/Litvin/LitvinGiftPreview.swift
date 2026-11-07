import Foundation

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
