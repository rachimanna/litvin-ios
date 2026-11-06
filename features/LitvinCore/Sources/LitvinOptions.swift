import Foundation

public struct LitvinOptions: Codable, Equatable {
    public var ghostMode = false
    public var ghostNoTyping = false
    public var ghostNoOnline = false
    public var ghostScheduleEnabled = false
    public var ghostStartMinute = 22 * 60
    public var ghostEndMinute = 8 * 60
    public var alibiEnabled = false
    public var alibiStartMinute = 9 * 60
    public var alibiEndMinute = 18 * 60
    public var saveDeleted = false
    public var saveEditHistory = false
    public var antiAds = false
    public var screenshotBypass = false
    public var forwardBypass = false
    public var infiniteSelfDestruct = false
    public var forwardScrub = false
    public var doubleBottom = false
    public var chatVault = false
    public var channelDigest = false
    public var contactProfile = false
    public var proxyPool = false
    public var messageNotes = true

    public init() {}
    public static var defaultSettings: LitvinOptions { LitvinOptions() }
}

public enum LitvinPolicy {
    public static let changed = Notification.Name("app.litvin.optionsChanged")
    private static let lock = NSLock()
    private static let defaultsKey = "app.litvin.options.v1"
    private static var cached: LitvinOptions = {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(LitvinOptions.self, from: data) else {
            return LitvinOptions()
        }
        return value
    }()

    public static var options: LitvinOptions {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    public static func update(_ transform: (inout LitvinOptions) -> Void) {
        lock.lock()
        transform(&cached)
        let data = try? JSONEncoder().encode(cached)
        if let data { UserDefaults.standard.set(data, forKey: defaultsKey) }
        lock.unlock()
        DispatchQueue.main.async { NotificationCenter.default.post(name: changed, object: nil) }
    }

    public static func replace(_ value: LitvinOptions) { update { $0 = value } }

    public static func inWindow(start: Int, end: Int, date: Date = Date()) -> Bool {
        guard (0..<1440).contains(start), (0..<1440).contains(end) else { return false }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start == end { return true }
        return start < end ? minute >= start && minute < end : minute >= start || minute < end
    }

    public static var ghostActive: Bool {
        let value = options
        return value.ghostMode || (value.ghostScheduleEnabled && inWindow(start: value.ghostStartMinute, end: value.ghostEndMinute))
    }

    public static var suppressTyping: Bool { ghostActive || options.ghostNoTyping }
    public static var suppressReadReceipts: Bool { ghostActive }
    public static func onlineStatus(requested: Bool) -> Bool {
        let value = options
        if ghostActive || value.ghostNoOnline { return false }
        if value.alibiEnabled && inWindow(start: value.alibiStartMinute, end: value.alibiEndMinute) { return true }
        return requested
    }
}
