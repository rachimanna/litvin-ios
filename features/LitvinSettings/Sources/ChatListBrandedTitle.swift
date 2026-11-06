import Foundation
import UIKit
import Display

/// Renders the Litvin wordmark into a UIImage for use as the chat-list title.
/// Called from a patch to `ChatListController.navigationBar.setContentNode`.
public enum ChatListBrandedTitle {
    public static let accentLight = UIColor(red: 200/255.0, green: 16/255.0, blue: 46/255.0, alpha: 1.0)
    public static let accentDark  = UIColor(red: 230/255.0, green: 57/255.0, blue: 70/255.0, alpha: 1.0)

    public static func image(dark: Bool = false, pointSize: CGFloat = 22) -> UIImage {
        let color = dark ? accentDark : accentLight
        let text = "Litvin"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: pointSize, weight: .heavy),
            .foregroundColor: color,
            .kern: -0.5,
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let size = attr.size()

        let markWidth: CGFloat = pointSize * 1.1
        let markPad: CGFloat = pointSize * 0.35
        let totalSize = CGSize(width: ceil(markWidth + markPad + size.width), height: ceil(max(size.height, pointSize)))

        let renderer = UIGraphicsImageRenderer(size: totalSize)
        return renderer.image { ctx in
            // Draw Λ with crossbar at the left as the mark
            let c = ctx.cgContext
            c.setStrokeColor(color.cgColor)
            c.setLineWidth(pointSize * 0.18)
            c.setLineCap(.square)
            c.setLineJoin(.miter)
            let left: CGFloat = 1
            let right = left + markWidth
            let mid = (left + right) / 2
            let top = totalSize.height * 0.12
            let bot = totalSize.height * 0.92
            c.move(to: CGPoint(x: left, y: bot))
            c.addLine(to: CGPoint(x: mid, y: top))
            c.addLine(to: CGPoint(x: right, y: bot))
            c.strokePath()
            let crossY = totalSize.height * 0.60
            c.move(to: CGPoint(x: left + markWidth * 0.20, y: crossY))
            c.addLine(to: CGPoint(x: right - markWidth * 0.20, y: crossY))
            c.strokePath()

            // Draw wordmark
            let textRect = CGRect(
                x: markWidth + markPad,
                y: (totalSize.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            attr.draw(in: textRect)
        }
    }
}
