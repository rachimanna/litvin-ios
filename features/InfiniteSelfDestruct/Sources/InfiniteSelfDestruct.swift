import Foundation
import Photos

public enum InfiniteSelfDestruct {
    public static func cancelCountdown(prefs: LitvinPreferences) -> Bool {
        return prefs.infiniteSelfDestruct
    }

    public static func suppressViewedReceipt(prefs: LitvinPreferences) -> Bool {
        // Default: silent view
        return prefs.infiniteSelfDestruct
    }

    public static func saveImageToLibrary(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    public static func saveVideoToLibrary(at fileURL: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }
}

import UIKit
