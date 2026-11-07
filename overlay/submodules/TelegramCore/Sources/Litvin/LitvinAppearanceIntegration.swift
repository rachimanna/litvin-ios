import Foundation
import SwiftSignalKit

public func litvinAppearanceUpdates() -> Signal<Void, NoError> {
    return Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: LitvinAppearance.changed, object: nil, queue: nil) { _ in subscriber.putNext(()) }
        subscriber.putNext(())
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
}

public func litvinDisplayStars(account: Int64, original: StarsAmount, enabled: Bool = true) -> StarsAmount {
    guard enabled, let stars = LitvinAppearance.state(account: account).stars else { return original }
    return StarsAmount(value: stars, nanos: 0)
}

public let litvinLocalGiftLabel = "Litvin: локальный подарок"
public func litvinIsLocalGift(_ gift: ProfileGiftsContext.State.StarGift) -> Bool {
    return gift.reference == nil && (gift.text == litvinLocalGiftLabel || gift.prepaidUpgradeHash == "litvin-preview")
}

public func litvinLocalGifts(account: Int64, peer: Int64) -> [StarGift] {
    return (LitvinAppearance.state(account: account).gifts[String(peer)] ?? [:]).sorted { $0.key < $1.key }.compactMap {
        if let gift = try? JSONDecoder().decode(StarGift.self, from: $0.value) { return gift }
        return (try? JSONDecoder().decode(StarGift.UniqueGift.self, from: $0.value)).map { .unique($0) }
    }.map { litvinGiftPresentation(account: account, sender: EnginePeer.Id(account), peer: EnginePeer.Id(peer), gift: $0, date: litvinGiftDate($0)) }
}

public func litvinProfileGifts(account: Int64, peer: Int64, collection: Int32?, state: ProfileGiftsContext.State, sender: EnginePeer? = nil) -> ProfileGiftsContext.State {
    guard collection == nil else { return state }
    var state = state
    let existing = Set(state.gifts.compactMap { gift -> String? in
        return litvinGiftKey(gift.gift)
    })
    let additions: [ProfileGiftsContext.State.StarGift] = litvinLocalGifts(account: account, peer: peer).filter { !existing.contains(litvinGiftKey($0)) }.map { gift in
        ProfileGiftsContext.State.StarGift(gift: gift, reference: nil, fromPeer: sender, date: litvinGiftDate(gift),
            text: litvinLocalGiftLabel, entities: nil, nameHidden: false, savedToProfile: true, pinnedToTop: false,
            convertStars: nil, canUpgrade: false, canExportDate: nil, upgradeStars: nil, transferStars: nil,
            canTransferDate: nil, canResaleDate: nil, collectionIds: nil, prepaidUpgradeHash: nil,
            upgradeSeparate: false, dropOriginalDetailsStars: nil, number: nil, isRefunded: false, canCraftAt: nil)
    }
    state.gifts = additions + state.gifts
    let visible = additions.filter { item in
        guard state.filter.contains(.displayed) else { return false }
        switch item.gift {
        case .unique: return state.filter.contains(.unique)
        case let .generic(gift): return gift.availability == nil ? state.filter.contains(.unlimited) : (gift.upgradeStars != nil ? state.filter.contains(.limitedUpgradable) : state.filter.contains(.limitedNonUpgradable))
        }
    }
    state.filteredGifts = visible + state.filteredGifts
    state.count = (state.count ?? Int32(state.filteredGifts.count - visible.count)) + Int32(visible.count)
    return state
}

public func litvinGiftKey(_ gift: StarGift) -> String {
    switch gift { case let .unique(gift): return gift.slug; case let .generic(gift): return "generic-\(gift.id)" }
}
public func litvinGiftTitle(_ gift: StarGift) -> String {
    switch gift { case let .unique(gift): return "\(gift.title) #\(gift.number)"; case let .generic(gift): return gift.title ?? "Подарок" }
}
