import Core
import CoreGraphics

extension WindowPositioning.Point {
    init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }

    var cgPoint: CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
}

extension WindowPositioning.Size {
    init(_ size: CGSize) {
        self.init(width: Double(size.width), height: Double(size.height))
    }

    var cgSize: CGSize {
        CGSize(width: CGFloat(width), height: CGFloat(height))
    }
}

extension WindowPositioning.Rect {
    init(_ rect: CGRect) {
        self.init(origin: WindowPositioning.Point(rect.origin), size: WindowPositioning.Size(rect.size))
    }

    var cgRect: CGRect {
        CGRect(origin: origin.cgPoint, size: size.cgSize)
    }
}
