import Foundation
import UIKit
import LocalAuthentication
import AsyncDisplayKit
import Display
import TelegramCore
import TelegramPresentationData
import AccountContext

// Chat lock: chosen chats open only after Face ID / Touch ID (or the iPhone
// passcode). A chat stays unlocked until Litvin goes to the background.

public enum LitvinChatLock {
    private static let key = "litvin.chatLock.peers"
    private static var unlockedPeers = Set<Int64>()
    private static var observer: NSObjectProtocol?

    private static func startObservingIfNeeded() {
        if self.observer != nil {
            return
        }
        self.observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { _ in
            LitvinChatLock.unlockedPeers.removeAll()
        })
    }

    public static var lockedPeers: Set<Int64> {
        let list = UserDefaults.standard.array(forKey: self.key) as? [NSNumber] ?? []
        return Set(list.map { $0.int64Value })
    }

    public static func isLocked(_ peerId: EnginePeer.Id) -> Bool {
        return self.lockedPeers.contains(peerId.toInt64())
    }

    public static func setLocked(_ peerId: EnginePeer.Id, _ locked: Bool) {
        var peers = self.lockedPeers
        if locked {
            peers.insert(peerId.toInt64())
        } else {
            peers.remove(peerId.toInt64())
            self.unlockedPeers.remove(peerId.toInt64())
        }
        UserDefaults.standard.set(peers.map { NSNumber(value: $0) }, forKey: self.key)
    }

    /// True when the chat is locked and was not unlocked during this session.
    public static func needsUnlock(_ peerId: EnginePeer.Id) -> Bool {
        self.startObservingIfNeeded()
        return self.isLocked(peerId) && !self.unlockedPeers.contains(peerId.toInt64())
    }

    public static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No Face ID and no passcode on the device: nothing to check against.
            completion(true)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason, reply: { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        })
    }

    public static func unlock(_ peerId: EnginePeer.Id, completion: @escaping (Bool) -> Void) {
        self.authenticate(reason: "Открыть закрытый чат", completion: { success in
            if success {
                LitvinChatLock.unlockedPeers.insert(peerId.toInt64())
            }
            completion(success)
        })
    }
}

/// Called at the start of navigateToChatController. Returns true when the
/// navigation was taken over: `proceed` runs again after a successful unlock.
public func litvinChatLockGate(peerId: EnginePeer.Id?, proceed: @escaping () -> Void) -> Bool {
    guard let peerId, LitvinChatLock.needsUnlock(peerId) else {
        return false
    }
    LitvinChatLock.unlock(peerId, completion: { success in
        if success {
            proceed()
        }
    })
    return true
}

private final class LitvinLockedPreviewNode: ASDisplayNode {
    private let iconNode: ImmediateTextNode
    private let titleNode: ImmediateTextNode

    init(theme: PresentationTheme) {
        self.iconNode = ImmediateTextNode()
        self.titleNode = ImmediateTextNode()
        super.init()
        self.backgroundColor = theme.list.plainBackgroundColor
        self.iconNode.attributedText = NSAttributedString(string: "🔒", font: Font.regular(56.0), textColor: theme.list.itemPrimaryTextColor)
        self.titleNode.attributedText = NSAttributedString(string: "Закрытый чат", font: Font.semibold(17.0), textColor: theme.list.itemSecondaryTextColor)
        self.addSubnode(self.iconNode)
        self.addSubnode(self.titleNode)
    }

    func update(size: CGSize) {
        let iconSize = self.iconNode.updateLayout(size)
        let titleSize = self.titleNode.updateLayout(size)
        let totalHeight = iconSize.height + 8.0 + titleSize.height
        let top = floor((size.height - totalHeight) / 2.0)
        self.iconNode.frame = CGRect(origin: CGPoint(x: floor((size.width - iconSize.width) / 2.0), y: top), size: iconSize)
        self.titleNode.frame = CGRect(origin: CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: top + iconSize.height + 8.0), size: titleSize)
    }
}

private final class LitvinLockedPreviewController: ViewController {
    private let theme: PresentationTheme

    init(theme: PresentationTheme) {
        self.theme = theme
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = LitvinLockedPreviewNode(theme: self.theme)
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        (self.displayNode as? LitvinLockedPreviewNode)?.update(size: layout.size)
    }
}

/// Chat-list long-press preview: a locked chat shows a lock instead of messages.
public func litvinLockedPreview(_ controller: ChatController, context: AccountContext) -> ViewController {
    guard let peerId = controller.chatLocation.peerId, LitvinChatLock.needsUnlock(peerId) else {
        return controller
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    return LitvinLockedPreviewController(theme: presentationData.theme)
}
