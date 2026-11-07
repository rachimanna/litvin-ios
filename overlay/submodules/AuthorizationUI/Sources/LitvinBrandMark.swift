import UIKit

func litvinBrandMark() -> UIImage {
    return UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { renderer in
        let context = renderer.cgContext
        context.scaleBy(x: 100.0 / 1024.0, y: 100.0 / 1024.0)
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024), cornerRadius: 224).addClip()
        let colors = [UIColor(red: 241/255.0, green: 44/255.0, blue: 84/255.0, alpha: 1).cgColor,
                      UIColor(red: 102/255.0, green: 40/255.0, blue: 184/255.0, alpha: 1).cgColor]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 1024, y: 1024), options: [])
        }
        UIColor.white.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 690, y: 345))
        path.addCurve(to: CGPoint(x: 371, y: 317), controlPoint1: CGPoint(x: 612, y: 258), controlPoint2: CGPoint(x: 472, y: 248))
        path.addCurve(to: CGPoint(x: 326, y: 672), controlPoint1: CGPoint(x: 250, y: 400), controlPoint2: CGPoint(x: 238, y: 568))
        path.addCurve(to: CGPoint(x: 674, y: 706), controlPoint1: CGPoint(x: 409, y: 773), controlPoint2: CGPoint(x: 566, y: 787))
        path.addCurve(to: CGPoint(x: 734, y: 618), controlPoint1: CGPoint(x: 705, y: 683), controlPoint2: CGPoint(x: 724, y: 652))
        path.addLine(to: CGPoint(x: 734, y: 520)); path.addLine(to: CGPoint(x: 540, y: 520))
        path.lineWidth = 88; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
        UIColor.white.setFill()
        let wing = UIBezierPath()
        wing.move(to: CGPoint(x: 570, y: 405)); wing.addLine(to: CGPoint(x: 819, y: 230))
        wing.addLine(to: CGPoint(x: 746, y: 468)); wing.addLine(to: CGPoint(x: 690, y: 393)); wing.close(); wing.fill()
    }
}
