import Foundation

public struct FakeGiftAsset: Equatable {
    public let id: String
    public let displayName: String
    public let lottieResourceName: String

    public init(id: String, displayName: String, lottieResourceName: String) {
        self.id = id
        self.displayName = displayName
        self.lottieResourceName = lottieResourceName
    }
}

public enum FakeGift {
    public static let catalog: [FakeGiftAsset] = [
        FakeGiftAsset(id: "cake",      displayName: "Cake",      lottieResourceName: "Cake"),
        FakeGiftAsset(id: "star",      displayName: "Star",      lottieResourceName: "Star"),
        FakeGiftAsset(id: "heart",     displayName: "Heart",     lottieResourceName: "Heart"),
        FakeGiftAsset(id: "trophy",    displayName: "Trophy",    lottieResourceName: "Trophy"),
        FakeGiftAsset(id: "celebrate", displayName: "Celebrate", lottieResourceName: "Celebrate"),
    ]
}

public final class FakeGiftStore {
    private var pending: [Int64: [FakeGiftAsset]] = [:]

    public init() {}

    public func stage(gift: FakeGiftAsset, for peerIdInt64: Int64) {
        var list = self.pending[peerIdInt64] ?? []
        list.append(gift)
        self.pending[peerIdInt64] = list
    }

    public func pending(for peerIdInt64: Int64) -> [FakeGiftAsset] {
        return self.pending[peerIdInt64] ?? []
    }

    public func clear(for peerIdInt64: Int64) {
        self.pending.removeValue(forKey: peerIdInt64)
    }
}
