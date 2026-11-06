import Foundation
import Postbox
import SwiftSignalKit

public struct LitvinStickerReference: Codable {
    public let id: Int64
    public let accessHash: Int64
}

public struct LitvinAccountContextState: Codable {
    public let account: Int64
    public let filters: [ChatListFilter]
    public let pinned: [Int64]
    public let archivedPinned: [Int64]
    public let stickers: [LitvinStickerReference]
}

public func litvinExportAccountContext(account: Account) -> Signal<LitvinAccountContextState, NoError> {
    return account.postbox.transaction { transaction -> LitvinAccountContextState in
        let filters = transaction.getPreferencesEntry(key: PreferencesKeys.chatListFilters)?.get(ChatListFiltersState.self)?.filters ?? []
        let pinned = transaction.getPinnedItemIds(groupId: .root).map { item -> Int64 in
            switch item { case let .peer(peer): return peer.toInt64() }
        }
        let archived = transaction.getPinnedItemIds(groupId: Namespaces.PeerGroup.archive).map { item -> Int64 in
            switch item { case let .peer(peer): return peer.toInt64() }
        }
        let stickers = transaction.getItemCollectionsInfos(namespace: Namespaces.ItemCollection.CloudStickerPacks).compactMap { entry -> LitvinStickerReference? in
            guard let info = entry.1 as? StickerPackCollectionInfo else { return nil }
            return LitvinStickerReference(id: info.id.id, accessHash: info.accessHash)
        }
        return LitvinAccountContextState(account: account.peerId.toInt64(), filters: filters, pinned: pinned, archivedPinned: archived, stickers: stickers)
    }
}

public func litvinRestoreAccountContext(account: Account, state: LitvinAccountContextState) -> Signal<Void, NoError> {
    guard state.account == account.peerId.toInt64(), state.filters.count <= 100,
          state.pinned.count <= 100, state.archivedPinned.count <= 100, state.stickers.count <= 1000 else { return .complete() }
    return account.postbox.transaction { transaction -> Void in
        _internal_updateChatListFiltersInteractively(transaction: transaction, { _ in state.filters })
        let pinned = state.pinned.map { PinnedItemId.peer(PeerId($0)) }
        let archived = state.archivedPinned.map { PinnedItemId.peer(PeerId($0)) }
        transaction.setPinnedItemIds(groupId: .root, itemIds: pinned)
        transaction.setPinnedItemIds(groupId: Namespaces.PeerGroup.archive, itemIds: archived)
        addSynchronizePinnedChatsOperation(transaction: transaction, groupId: .root)
        addSynchronizePinnedChatsOperation(transaction: transaction, groupId: Namespaces.PeerGroup.archive)
    }
}
