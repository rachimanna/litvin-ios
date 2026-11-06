import Foundation
import Postbox
import SwiftSignalKit

public struct LitvinPreferences: Codable, Equatable, PreferencesEntry {
    public var ghostMode: Bool
    public var ghostNoTyping: Bool
    public var ghostNoOnline: Bool
    public var ghostScheduleEnabled: Bool
    public var saveDeleted: Bool
    public var saveEditHistory: Bool
    public var antiAds: Bool
    public var screenshotBypass: Bool
    public var forwardBypass: Bool
    public var infiniteSelfDestruct: Bool
    public var forwardScrub: Bool
    public var doubleBottom: Bool
    public var chatVault: Bool
    public var channelDigest: Bool
    public var contactProfile: Bool
    public var proxyPool: Bool
    public var localAI: Bool

    public static let `default` = LitvinPreferences(
        ghostMode: false,
        ghostNoTyping: false,
        ghostNoOnline: false,
        ghostScheduleEnabled: false,
        saveDeleted: true,
        saveEditHistory: true,
        antiAds: true,
        screenshotBypass: true,
        forwardBypass: true,
        infiniteSelfDestruct: true,
        forwardScrub: false,
        doubleBottom: false,
        chatVault: false,
        channelDigest: false,
        contactProfile: false,
        proxyPool: false,
        localAI: false
    )

    public func isEqual(to: PreferencesEntry) -> Bool {
        guard let other = to as? LitvinPreferences else { return false }
        return self == other
    }
}

public extension PreferencesKeys {
    static let litvinMain = ValueBoxKey(length: 4).setInt32(0, value: 0x4C545659) // 'LTVY'
}

public func updateLitvinPreferences(
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    _ mutate: @escaping (LitvinPreferences) -> LitvinPreferences
) -> Signal<Never, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(SharedDataKeys.litvinPreferences) { entry in
            let current = entry?.get(LitvinPreferences.self) ?? .default
            return PreferencesEntry(mutate(current))
        }
    }
    |> ignoreValues
}

public extension SharedDataKeys {
    static let litvinPreferences = ValueBoxKey(length: 4).setInt32(0, value: 0x4C545658) // 'LTVX'
}
