import Foundation

public enum ForwardBypass {
    public static func allowCopy(prefs: LitvinPreferences) -> Bool {
        return prefs.forwardBypass
    }

    public static func allowForward(prefs: LitvinPreferences) -> Bool {
        return prefs.forwardBypass
    }
}
