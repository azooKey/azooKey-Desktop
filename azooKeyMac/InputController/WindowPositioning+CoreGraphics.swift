import AppKit
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

enum ScreenLookup {
    /// 与えられたグローバル座標を含む `NSScreen` を返す。
    ///
    /// 包含判定には `NSScreen.frame`（メニューバー／Dock を含むディスプレイ全体）を用いる。
    /// `visibleFrame` で判定するとメニューバー直下や Dock 領域に近い座標で外れることがあるため、
    /// 包含と利用領域は意図的に分離している（呼び出し側でクランプには `visibleFrame` を渡す想定）。
    ///
    /// どの screen にも含まれなかった場合のフォールバック順は以下:
    /// 1. point に最も近い `NSScreen`（ディスプレイ間の隙間や境界上の座標で滑らかに収束させるため）
    /// 2. `fallbackWindow?.screen`（呼び出し側がウィンドウを持っている場合の最低限の保証）
    /// 3. `NSScreen.main`
    ///
    /// `fallbackWindow?.screen` をあえて最近接 screen より後ろに置くのは、本ヘルパーの主目的が
    /// 「`window.screen` がカーソル所在のディスプレイと一致しない問題」を避けることにあり、
    /// 異常座標時に古いスクリーンを返す挙動を許容したくないため。
    static func screen(containing point: CGPoint, fallbackWindow: NSWindow? = nil) -> NSScreen? {
        if let hit = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            return hit
        }
        if let nearest = NSScreen.screens.min(by: { lhs, rhs in
            squaredDistance(from: point, to: lhs.frame) < squaredDistance(from: point, to: rhs.frame)
        }) {
            return nearest
        }
        if let windowScreen = fallbackWindow?.screen {
            return windowScreen
        }
        return NSScreen.main
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        return dx * dx + dy * dy
    }
}
