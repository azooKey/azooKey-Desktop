public enum WindowPositioning {
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
        var newWindowFrame = currentFrame
        newWindowFrame.size = desiredSize

        let cursorY = cursorLocation.y
        if cursorY - desiredSize.height < screenRect.origin.y {
            newWindowFrame.origin = Point(x: cursorLocation.x, y: cursorLocation.y + cursorHeight)
        } else {
            newWindowFrame.origin = Point(x: cursorLocation.x, y: cursorLocation.y - desiredSize.height - cursorHeight)
        }

        if newWindowFrame.maxX > screenRect.maxX {
            newWindowFrame.origin.x = screenRect.maxX - newWindowFrame.width
        }
        return newWindowFrame
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
