import Core
import Testing

@Test func testFrameNearCursorPlacesBelowWhenNotEnoughSpace() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 40, height: 20)
    )
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 100, height: 100)
    )
    let cursorLocation = WindowPositioning.Point(x: 50, y: 10)
    let desiredSize = WindowPositioning.Size(width: 40, height: 30)

    let frame = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize
    )

    #expect(frame.origin == WindowPositioning.Point(x: 50, y: 26))
    #expect(frame.size == desiredSize)
}

@Test func testFrameNearCursorAdjustsRightEdge() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 20, height: 20)
    )
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 100, height: 100)
    )
    let cursorLocation = WindowPositioning.Point(x: 95, y: 50)
    let desiredSize = WindowPositioning.Size(width: 20, height: 20)

    let frame = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize
    )

    #expect(frame.origin == WindowPositioning.Point(x: 80, y: 14))
}

@Test func testFrameRightOfAnchorClampsToVisibleFrame() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 30, height: 20)
    )
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 100, height: 100)
    )
    let anchorFrame = WindowPositioning.Rect(
        origin: .init(x: 80, y: 10),
        size: .init(width: 30, height: 20)
    )

    let frame = WindowPositioning.frameRightOfAnchor(
        currentFrame: currentFrame,
        anchorFrame: anchorFrame,
        screenRect: screenRect,
        gap: 8
    )

    #expect(frame.origin == WindowPositioning.Point(x: 70, y: 10))
    #expect(frame.size == currentFrame.size)
}

@Test func testPromptWindowOriginMovesAboveWhenBelowWouldOverflow() async throws {
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 100, height: 100)
    )
    let cursorLocation = WindowPositioning.Point(x: 10, y: 10)
    let windowSize = WindowPositioning.Size(width: 40, height: 30)

    let origin = WindowPositioning.promptWindowOrigin(
        cursorLocation: cursorLocation,
        windowSize: windowSize,
        screenRect: screenRect
    )

    #expect(origin == WindowPositioning.Point(x: 20, y: 40))
}

@Test func testPromptWindowOriginClampsToRightEdge() async throws {
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 100, height: 100)
    )
    let cursorLocation = WindowPositioning.Point(x: 95, y: 50)
    let windowSize = WindowPositioning.Size(width: 40, height: 30)

    let origin = WindowPositioning.promptWindowOrigin(
        cursorLocation: cursorLocation,
        windowSize: windowSize,
        screenRect: screenRect
    )

    #expect(origin == WindowPositioning.Point(x: 40, y: 50))
}
