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
    return gift.reference == nil && gift.text == litvinLocalGiftLabel
}

public func litvinLocalGifts(account: Int64, peer: Int64) -> [StarGift.UniqueGift] {
    return (LitvinAppearance.state(account: account).gifts[String(peer)] ?? [:]).sorted { $0.key < $1.key }.compactMap {
        try? JSONDecoder().decode(StarGift.UniqueGift.self, from: $0.value)
    }
}

public func litvinProfileGifts(account: Int64, peer: Int64, collection: Int32?, state: ProfileGiftsContext.State) -> ProfileGiftsContext.State {
    guard collection == nil else { return state }
    var state = state
    let existing = Set(state.gifts.compactMap { gift -> String? in
        if case let .unique(unique) = gift.gift { return unique.slug }; return nil
    })
    let additions: [ProfileGiftsContext.State.StarGift] = litvinLocalGifts(account: account, peer: peer).filter { !existing.contains($0.slug) }.map { unique in
        ProfileGiftsContext.State.StarGift(gift: .unique(unique), reference: nil, fromPeer: nil, date: 0,
            text: litvinLocalGiftLabel, entities: nil, nameHidden: true, savedToProfile: true, pinnedToTop: false,
            convertStars: nil, canUpgrade: false, canExportDate: nil, upgradeStars: nil, transferStars: nil,
            canTransferDate: nil, canResaleDate: nil, collectionIds: nil, prepaidUpgradeHash: nil,
            upgradeSeparate: false, dropOriginalDetailsStars: nil, number: nil, isRefunded: false, canCraftAt: nil)
    }
    state.gifts = additions + state.gifts
    if state.filter.contains(.unique) && state.filter.contains(.displayed) {
        state.filteredGifts = additions + state.filteredGifts
        state.count = (state.count ?? Int32(state.filteredGifts.count - additions.count)) + Int32(additions.count)
    }
    return state
}
