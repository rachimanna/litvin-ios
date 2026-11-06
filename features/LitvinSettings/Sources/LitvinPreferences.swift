import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

public struct LitvinPreferences: Codable, Equatable {
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

    public static let defaultValue = LitvinPreferences(
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
}

public extension SharedDataKeys {
    static let litvinPreferences: ValueBoxKey = {
        let key = ValueBoxKey(length: 4)
        key.setInt32(0, value: 0x4C545658) // 'LTVX'
        return key
    }()
}

public func litvinPreferences(_ shared: SharedData) -> LitvinPreferences {
    if let entry = shared.entries[SharedDataKeys.litvinPreferences],
       let data = entry.data,
       let value = try? JSONDecoder().decode(LitvinPreferences.self, from: data) {
        return value
    }
    return .defaultValue
}

public func updateLitvinPreferences(
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    _ mutate: @escaping (LitvinPreferences) -> LitvinPreferences
) -> Signal<Never, NoError> {
    return accountManager.transaction { transaction in
        transaction.updateSharedData(SharedDataKeys.litvinPreferences) { entry in
            let current: LitvinPreferences
            if let entry = entry, let data = entry.data,
               let value = try? JSONDecoder().decode(LitvinPreferences.self, from: data) {
                current = value
            } else {
                current = .defaultValue
            }
            let updated = mutate(current)
            let data = (try? JSONEncoder().encode(updated)) ?? Data()
            return SharedDataEntry(data: data)
        }
    }
    |> ignoreValues
}
