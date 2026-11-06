import Foundation

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

    public static var defaultSettings: LitvinPreferences {
        return LitvinPreferences(
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

    public init(ghostMode: Bool, ghostNoTyping: Bool, ghostNoOnline: Bool, ghostScheduleEnabled: Bool, saveDeleted: Bool, saveEditHistory: Bool, antiAds: Bool, screenshotBypass: Bool, forwardBypass: Bool, infiniteSelfDestruct: Bool, forwardScrub: Bool, doubleBottom: Bool, chatVault: Bool, channelDigest: Bool, contactProfile: Bool, proxyPool: Bool, localAI: Bool) {
        self.ghostMode = ghostMode
        self.ghostNoTyping = ghostNoTyping
        self.ghostNoOnline = ghostNoOnline
        self.ghostScheduleEnabled = ghostScheduleEnabled
        self.saveDeleted = saveDeleted
        self.saveEditHistory = saveEditHistory
        self.antiAds = antiAds
        self.screenshotBypass = screenshotBypass
        self.forwardBypass = forwardBypass
        self.infiniteSelfDestruct = infiniteSelfDestruct
        self.forwardScrub = forwardScrub
        self.doubleBottom = doubleBottom
        self.chatVault = chatVault
        self.channelDigest = channelDigest
        self.contactProfile = contactProfile
        self.proxyPool = proxyPool
        self.localAI = localAI
    }
}
