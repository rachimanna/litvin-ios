import Foundation
import SwiftSignalKit
import Postbox

public enum GhostMode {
    public static func isActive(prefs: LitvinPreferences) -> Bool {
        return prefs.ghostMode
    }

    public static func allowSendReadReceipt(prefs: LitvinPreferences, peerId: PeerId) -> Bool {
        if prefs.ghostMode { return false }
        return true
    }

    public static func allowEmitTyping(prefs: LitvinPreferences) -> Bool {
        return !prefs.ghostNoTyping
    }

    public static func allowReportOnline(prefs: LitvinPreferences) -> Bool {
        return !prefs.ghostNoOnline
    }
}
