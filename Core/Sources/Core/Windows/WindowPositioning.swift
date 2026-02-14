public enum WindowPositioning {
    /// 候補ウィンドウの配置方向
    public enum Direction: Equatable {
        case above  // カーソルの上（macOS座標で y が大きい方向）
        case below  // カーソルの下（macOS座標で y が小さい方向）
    }

    /// frameNearCursor の戻り値（位置 + 実際に選択された配置方向）
    public struct PositionResult: Equatable {
        public var frame: Rect
        public var direction: Direction

        public init(frame: Rect, direction: Direction) {
            self.frame = frame
            self.direction = direction
        }
    }

    public struct Point: Equatable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct Size: Equatable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    public struct Rect: Equatable {
        public var origin: Point
        public var size: Size

        public init(origin: Point, size: Size) {
            self.origin = origin
            self.size = size
        }

        public var minX: Double {
            origin.x
        }
        public var minY: Double {
            origin.y
        }
        public var maxX: Double {
            origin.x + size.width
        }
        public var maxY: Double {
            origin.y + size.height
        }
        public var width: Double {
            size.width
        }
        public var height: Double {
            size.height
        }
    }

    public static func frameNearCursor(
        currentFrame: Rect,
        screenRect: Rect,
        cursorLocation: Point,
        desiredSize: Size,
        cursorHeight: Double = 16
    ) -> Rect {
        frameNearCursor(
            currentFrame: currentFrame,
            screenRect: screenRect,
            cursorLocation: cursorLocation,
            desiredSize: desiredSize,
            cursorHeight: cursorHeight,
            preferredDirection: nil
        ).frame
    }

    public static func frameNearCursor(
        currentFrame: Rect,
        screenRect: Rect,
        cursorLocation: Point,
        desiredSize: Size,
        cursorHeight: Double = 16,
        preferredDirection: Direction?
    ) -> PositionResult {
        var newWindowFrame = currentFrame
        newWindowFrame.size = desiredSize

        let cursorY = cursorLocation.y

        // 各方向に収まるかの判定
        let fitsBelow = (cursorY - desiredSize.height - cursorHeight) >= screenRect.origin.y
        let fitsAbove = (cursorY + cursorHeight + desiredSize.height) <= screenRect.maxY

        // 方向の決定（ヒステリシス付き）
        let direction: Direction
        if let preferred = preferredDirection {
            // 前回の方向に収まるならそのまま維持（ヒステリシス）
            switch preferred {
            case .below where fitsBelow:
                direction = .below
            case .above where fitsAbove:
                direction = .above
            default:
                // 前回の方向に収まらない → フォールバック
                if fitsBelow {
                    direction = .below
                } else if fitsAbove {
                    direction = .above
                } else {
                    // どちらにも収まらない → スペースが広い方
                    let spaceBelow = cursorY - cursorHeight - screenRect.origin.y
                    let spaceAbove = screenRect.maxY - (cursorY + cursorHeight)
                    direction = spaceBelow >= spaceAbove ? .below : .above
                }
            }
        } else {
            // 初回（preferredDirection == nil）→ 既存ロジックと同一
            if cursorY - desiredSize.height < screenRect.origin.y {
                direction = .above
            } else {
                direction = .below
            }
        }

        // 配置位置の計算
        switch direction {
        case .above:
            newWindowFrame.origin = Point(x: cursorLocation.x, y: cursorLocation.y + cursorHeight)
        case .below:
            newWindowFrame.origin = Point(x: cursorLocation.x, y: cursorLocation.y - desiredSize.height - cursorHeight)
        }

        // 水平クランプ
        if newWindowFrame.maxX > screenRect.maxX {
            newWindowFrame.origin.x = screenRect.maxX - newWindowFrame.width
        }
        if newWindowFrame.minX < screenRect.minX {
            newWindowFrame.origin.x = screenRect.minX
        }

        // 垂直クランプ（両方向を順に適用。ウィンドウが画面より大きい場合は minY を優先）
        if newWindowFrame.maxY > screenRect.maxY {
            newWindowFrame.origin.y = screenRect.maxY - newWindowFrame.height
        }
        if newWindowFrame.minY < screenRect.minY {
            newWindowFrame.origin.y = screenRect.minY
        }

        return PositionResult(frame: newWindowFrame, direction: direction)
    }

    public static func frameRightOfAnchor(
        currentFrame: Rect,
        anchorFrame: Rect,
        screenRect: Rect,
        gap: Double = 8
    ) -> Rect {
        var frame = currentFrame
        frame.origin.x = anchorFrame.maxX + gap
        frame.origin.y = anchorFrame.origin.y

        if frame.minX < screenRect.minX {
            frame.origin.x = screenRect.minX
        } else if frame.maxX > screenRect.maxX {
            frame.origin.x = screenRect.maxX - frame.width
        }

        if frame.minY < screenRect.minY {
            frame.origin.y = screenRect.minY
        } else if frame.maxY > screenRect.maxY {
            frame.origin.y = screenRect.maxY - frame.height
        }

        return frame
    }

    public static func promptWindowOrigin(
        cursorLocation: Point,
        windowSize: Size,
        screenRect: Rect,
        offsetX: Double = 10,
        belowOffset: Double = 20,
        aboveOffset: Double = 30,
        padding: Double = 20
    ) -> Point {
        var origin = cursorLocation
        origin.x += offsetX
        origin.y -= windowSize.height + belowOffset

        if origin.x + windowSize.width + padding > screenRect.maxX {
            origin.x = screenRect.maxX - windowSize.width - padding
        }

        if origin.x < screenRect.minX + padding {
            origin.x = screenRect.minX + padding
        }

        if origin.y < screenRect.minY + padding {
            origin.y = cursorLocation.y + aboveOffset
            if origin.y + windowSize.height + padding > screenRect.maxY {
                origin.y = screenRect.maxY - windowSize.height - padding
            }
        }

        if origin.y + windowSize.height + padding > screenRect.maxY {
            origin.y = screenRect.maxY - windowSize.height - padding
        }

        return origin
    }
}
