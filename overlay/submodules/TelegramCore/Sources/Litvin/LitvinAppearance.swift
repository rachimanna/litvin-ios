import Foundation

/// Presentation overrides only. Never changes account credentials or entitlements.
public struct LitvinAppearanceState: Codable, Equatable {
    public var giftPreviewEnabled: Bool? = false
    public var giftPreviewPrice: Int64?
    public var premium = false
    public var phone: String?
    public var stars: Int64?
    public var gifts: [String: [String: Data]] = [:]
    public init() {}
}

public enum LitvinAppearance {
    public static let changed = Notification.Name("app.litvin.appearanceChanged")
    private static let lock = NSLock()
    private static let prefix = "app.litvin.appearance.v1."
    public static let maximumStars: Int64 = 999_999_999_999

    public static func state(account: Int64) -> LitvinAppearanceState {
        lock.lock()
        defer { lock.unlock() }
        return read(account)
    }
    private static func read(_ account: Int64) -> LitvinAppearanceState {
        guard let data = UserDefaults.standard.data(forKey: prefix + String(account)),
              data.count <= 8 * 1024 * 1024,
              let value = try? JSONDecoder().decode(LitvinAppearanceState.self, from: data) else { return .init() }
        return value
    }
    @discardableResult public static func update(account: Int64, _ transform: (inout LitvinAppearanceState) -> Void) -> Bool {
        lock.lock()
        var value = read(account)
        transform(&value)
        let valid = value.phone.map { $0.count <= 64 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) } ?? true
        let starsValid = value.stars.map { (0...maximumStars).contains($0) } ?? true
        let priceValid = value.giftPreviewPrice.map { (0...maximumStars).contains($0) } ?? true
        let giftsValid = value.gifts.values.reduce(0) { $0 + $1.count } <= 100
            && value.gifts.values.allSatisfy { $0.allSatisfy { $0.key.count <= 128 && $0.value.count <= 256 * 1024 } }
        guard valid, starsValid, priceValid, giftsValid, let data = try? JSONEncoder().encode(value), data.count <= 8 * 1024 * 1024 else { lock.unlock(); return false }
        UserDefaults.standard.set(data, forKey: prefix + String(account))
        lock.unlock()
        DispatchQueue.main.async { NotificationCenter.default.post(name: changed, object: account) }
        return true
    }
    public static func phone(account: Int64, peer: Int64, original: String) -> String {
        account == peer ? (state(account: account).phone ?? original) : original
    }
    public static func premium(account: Int64, peer: Int64, original: Bool) -> Bool {
        original || (account == peer && state(account: account).premium)
    }
    public static func reset(account: Int64) { _ = update(account: account) { $0 = .init() } }
}
