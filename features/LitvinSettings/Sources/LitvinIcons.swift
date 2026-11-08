import Foundation
import UIKit

// iOS 26 Settings-style row icons: a white SF Symbol on a coloured rounded square.

public enum LitvinIconColor {
    case gray, blue, indigo, purple, pink, red, orange, yellow, green, teal, black

    var colors: (UIColor, UIColor) {
        switch self {
        case .gray: return (litvinColor(0x9A9AA1), litvinColor(0x7C7C83))
        case .blue: return (litvinColor(0x3B9BFF), litvinColor(0x0A72F0))
        case .indigo: return (litvinColor(0x6E6CF5), litvinColor(0x4B48DB))
        case .purple: return (litvinColor(0xC66BF0), litvinColor(0x9C3FD6))
        case .pink: return (litvinColor(0xFF5C8A), litvinColor(0xE8306A))
        case .red: return (litvinColor(0xFF5B52), litvinColor(0xE5352C))
        case .orange: return (litvinColor(0xFFA733), litvinColor(0xF5830A))
        case .yellow: return (litvinColor(0xFFD43B), litvinColor(0xF5B80A))
        case .green: return (litvinColor(0x4CD964), litvinColor(0x28B946))
        case .teal: return (litvinColor(0x4AD0E6), litvinColor(0x16A9C9))
        case .black: return (litvinColor(0x2C2C2E), litvinColor(0x000000))
        }
    }
}

private func litvinColor(_ rgb: UInt32) -> UIColor {
    return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255.0, green: CGFloat((rgb >> 8) & 0xFF) / 255.0, blue: CGFloat(rgb & 0xFF) / 255.0, alpha: 1.0)
}

private var litvinIconCache: [String: UIImage] = [:]

public func litvinRowIcon(_ symbol: String, _ color: LitvinIconColor) -> UIImage? {
    let key = "\(symbol)|\(color)"
    if let cached = litvinIconCache[key] {
        return cached
    }
    let size = CGSize(width: 30.0, height: 30.0)
    let configuration = UIImage.SymbolConfiguration(pointSize: 15.0, weight: .semibold)
    let glyph = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(.white, renderingMode: .alwaysOriginal)
    let (top, bottom) = color.colors
    let image = UIGraphicsImageRenderer(size: size).image { context in
        let rect = CGRect(origin: .zero, size: size)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 8.0)
        path.addClip()
        let space = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(colorsSpace: space, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0.0, 1.0]) {
            context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: size.height), options: [])
        }
        if let glyph {
            let scale = min(1.0, 19.0 / max(glyph.size.width, glyph.size.height))
            let glyphSize = CGSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
            glyph.draw(in: CGRect(x: (size.width - glyphSize.width) / 2.0, y: (size.height - glyphSize.height) / 2.0, width: glyphSize.width, height: glyphSize.height))
        }
    }
    litvinIconCache[key] = image
    return image
}
