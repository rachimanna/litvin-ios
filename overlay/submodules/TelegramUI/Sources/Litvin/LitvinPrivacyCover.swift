import Foundation
import UIKit

// Branded cover shown over the app while it is inactive, so the iOS app
// switcher snapshot shows the Litvin screen instead of the user's chats.
public final class LitvinPrivacyCover {
    public static let shared = LitvinPrivacyCover()

    private weak var window: UIWindow?
    private var coverView: UIView?
    private var observers: [NSObjectProtocol] = []

    private init() {
    }

    public func install(window: UIWindow) {
        self.window = window
        if !self.observers.isEmpty {
            return
        }
        let center = NotificationCenter.default
        self.observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.show()
        }))
        self.observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.show()
        }))
        self.observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.hide()
        }))
    }

    private func show() {
        guard let window = self.window else {
            return
        }
        if let coverView = self.coverView {
            coverView.layer.removeAllAnimations()
            coverView.alpha = 1.0
            coverView.frame = window.bounds
            window.bringSubviewToFront(coverView)
            return
        }
        let coverView = LitvinCoverView(frame: window.bounds)
        coverView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(coverView)
        self.coverView = coverView
    }

    private func hide() {
        guard let coverView = self.coverView else {
            return
        }
        UIView.animate(withDuration: 0.2, animations: {
            coverView.alpha = 0.0
        }, completion: { [weak self] finished in
            if finished, let self, self.coverView === coverView {
                coverView.removeFromSuperview()
                self.coverView = nil
            }
        })
    }
}

private func litvinColor(_ rgb: UInt32) -> UIColor {
    return UIColor(red: CGFloat((rgb >> 16) & 0xff) / 255.0, green: CGFloat((rgb >> 8) & 0xff) / 255.0, blue: CGFloat(rgb & 0xff) / 255.0, alpha: 1.0)
}

private final class LitvinCoverView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let logoView: UIView
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        if let data = Data(base64Encoded: litvinCustomLogoBase64), let image = UIImage(data: data) {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            self.logoView = imageView
        } else {
            self.logoView = LitvinMarkView()
        }
        super.init(frame: frame)

        self.isUserInteractionEnabled = true
        self.gradientLayer.colors = [litvinColor(0xE0163A).cgColor, litvinColor(0x9E1250).cgColor, litvinColor(0x4B1683).cgColor]
        self.gradientLayer.locations = [0.0, 0.5, 1.0]
        self.gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.layer.addSublayer(self.gradientLayer)

        self.logoView.backgroundColor = .clear
        self.addSubview(self.logoView)

        self.titleLabel.text = "Litvin"
        self.titleLabel.textColor = .white
        self.titleLabel.font = UIFont.systemFont(ofSize: 40.0, weight: .heavy)
        self.titleLabel.textAlignment = .center
        self.addSubview(self.titleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.gradientLayer.frame = self.bounds

        let logoSize: CGFloat = self.logoView is UIImageView ? 160.0 : 120.0
        self.logoView.frame = CGRect(x: floor((self.bounds.width - logoSize) / 2.0), y: floor(self.bounds.height / 2.0 - logoSize), width: logoSize, height: logoSize)

        self.titleLabel.sizeToFit()
        let titleSize = self.titleLabel.bounds.size
        self.titleLabel.frame = CGRect(x: floor((self.bounds.width - titleSize.width) / 2.0), y: self.logoView.frame.maxY + 18.0, width: titleSize.width, height: titleSize.height)
    }
}

// White disc with the crimson Litvin mark (same geometry as branding/icon.svg).
private final class LitvinMarkView: UIView {
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        let size = min(self.bounds.width, self.bounds.height)
        let circleRect = CGRect(x: (self.bounds.width - size) / 2.0, y: (self.bounds.height - size) / 2.0, width: size, height: size)

        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: circleRect)

        let scale = size * 0.56 / 544.0
        let markHeight = 552.0 * scale
        let left = circleRect.midX - 272.0 * scale
        let top = circleRect.midY - markHeight / 2.0
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: left + (x - 240.0) * scale, y: top + (y - 240.0) * scale)
        }

        context.setStrokeColor(litvinColor(0xD01030).cgColor)
        context.setLineWidth(88.0 * scale)
        context.setLineCap(.square)
        context.setLineJoin(.miter)
        context.move(to: point(240.0, 792.0))
        context.addLine(to: point(512.0, 240.0))
        context.addLine(to: point(784.0, 792.0))
        context.strokePath()
        context.move(to: point(344.0, 584.0))
        context.addLine(to: point(680.0, 584.0))
        context.strokePath()
    }
}
