import Foundation

public enum ScreenshotBypass {
    public static func allowCapture(prefs: LitvinPreferences) -> Bool {
        return prefs.screenshotBypass
    }
}
