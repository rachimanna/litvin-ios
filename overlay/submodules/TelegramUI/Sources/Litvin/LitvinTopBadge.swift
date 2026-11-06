import Foundation
import UIKit
import TelegramCore

// "Litvin" pill placed exactly under the Dynamic Island (or the notch).
// On the device the island covers it; on screenshots and screen recordings the
// island is not captured, so the pill shows up at the top like a watermark.
public final class LitvinTopBadge {
    public static let shared = LitvinTopBadge()

    private var badgeWindow: UIWindow?
    private weak var mainWindow: UIWindow?
    private var observers: [NSObjectProtocol] = []

    private init() {
    }

    public func install(window: UIWindow) {
        self.mainWindow = window
        if self.observers.isEmpty {
            let center = NotificationCenter.default
            self.observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { [weak self] _ in
                self?.update()
            }))
            self.observers.append(center.addObserver(forName: Notification.Name("LitvinFlagsChanged"), object: nil, queue: .main, using: { [weak self] _ in
                self?.update()
            }))
            self.observers.append(center.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
                self?.update()
            }))
        }
        DispatchQueue.main.async { [weak self] in
            self?.update()
        }
    }

    public func update() {
        guard let mainWindow = self.mainWindow, LitvinFlags.topBadge else {
            self.badgeWindow?.isHidden = true
            return
        }
        let topInset = mainWindow.safeAreaInsets.top
        let bounds = mainWindow.bounds
        // Portrait only, and only on devices that have an island or a notch to hide it behind.
        if topInset < 44.0 || bounds.width > bounds.height {
            self.badgeWindow?.isHidden = true
            return
        }

        let frame: CGRect
        if topInset >= 59.0 {
            // Dynamic Island: 126 x 37.33 pt at y = 11. Stay fully inside it.
            frame = CGRect(x: floor((bounds.width - 116.0) / 2.0), y: 13.0, width: 116.0, height: 33.0)
        } else {
            // Notch: hide inside its upper part.
            frame = CGRect(x: floor((bounds.width - 104.0) / 2.0), y: 3.0, width: 104.0, height: 26.0)
        }

        let badgeWindow: UIWindow
        if let current = self.badgeWindow {
            badgeWindow = current
        } else {
            if let scene = mainWindow.windowScene {
                badgeWindow = UIWindow(windowScene: scene)
            } else {
                badgeWindow = UIWindow(frame: frame)
            }
            badgeWindow.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.statusBar.rawValue + 1.0)
            badgeWindow.isUserInteractionEnabled = false
            badgeWindow.backgroundColor = .clear
            badgeWindow.addSubview(LitvinBadgeView(frame: CGRect(origin: .zero, size: frame.size)))
            self.badgeWindow = badgeWindow
        }
        badgeWindow.frame = frame
        for subview in badgeWindow.subviews {
            subview.frame = CGRect(origin: .zero, size: frame.size)
            subview.setNeedsLayout()
        }
        badgeWindow.isHidden = false
    }
}

private final class LitvinBadgeView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.isUserInteractionEnabled = false
        self.clipsToBounds = true

        // Black and white, like the app icon.
        self.backgroundColor = .black
        self.layer.borderColor = UIColor(white: 1.0, alpha: 0.18).cgColor
        self.layer.borderWidth = 1.0

        if let data = Data(base64Encoded: litvinCustomLogoBase64), let image = UIImage(data: data) {
            self.iconView.image = image
        }
        self.iconView.contentMode = .scaleAspectFit
        self.addSubview(self.iconView)

        self.titleLabel.text = "LITVIN"
        self.titleLabel.textColor = .white
        let baseFont = UIFont.systemFont(ofSize: 17.0, weight: .black)
        if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) {
            self.titleLabel.font = UIFont(descriptor: descriptor, size: 17.0)
        } else {
            self.titleLabel.font = baseFont
        }
        self.titleLabel.adjustsFontSizeToFitWidth = true
        self.titleLabel.minimumScaleFactor = 0.6
        self.addSubview(self.titleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let size = self.bounds.size
        self.layer.cornerRadius = size.height / 2.0

        let iconSize = size.height - 8.0
        let hasIcon = self.iconView.image != nil
        self.iconView.isHidden = !hasIcon

        self.titleLabel.sizeToFit()
        let titleWidth = min(self.titleLabel.bounds.width, size.width - (hasIcon ? iconSize + 18.0 : 14.0))
        let contentWidth = (hasIcon ? iconSize + 5.0 : 0.0) + titleWidth
        var x = floor((size.width - contentWidth) / 2.0)
        if hasIcon {
            self.iconView.frame = CGRect(x: x, y: 4.0, width: iconSize, height: iconSize)
            x += iconSize + 5.0
        }
        self.titleLabel.frame = CGRect(x: x, y: 0.0, width: titleWidth, height: size.height)
    }
}
