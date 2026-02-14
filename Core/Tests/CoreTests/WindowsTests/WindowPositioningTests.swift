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

// MARK: - frameNearCursor with preferredDirection (ヒステリシス)

@Test func testFrameNearCursorHysteresisKeepsBelowDirection() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 200, height: 252)
    )
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 800, height: 600)
    )
    // カーソルが画面中央 → 上にも下にも収まる
    let cursorLocation = WindowPositioning.Point(x: 100, y: 300)
    let desiredSize = WindowPositioning.Size(width: 200, height: 252)

    let result = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize,
        preferredDirection: .below
    )
    #expect(result.direction == .below)
}

@Test func testFrameNearCursorHysteresisKeepsAboveDirection() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 200, height: 252)
    )
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 800, height: 600)
    )
    let cursorLocation = WindowPositioning.Point(x: 100, y: 300)
    let desiredSize = WindowPositioning.Size(width: 200, height: 252)

    let result = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize,
        preferredDirection: .above
    )
    #expect(result.direction == .above)
}

@Test func testFrameNearCursorHysteresisFallsBackFromBelow() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 200, height: 252)
    )
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 800, height: 600)
    )
    // カーソルが画面下端付近 → 下には収まらない
    let cursorLocation = WindowPositioning.Point(x: 100, y: 30)
    let desiredSize = WindowPositioning.Size(width: 200, height: 252)

    let result = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize,
        preferredDirection: .below
    )
    // 下に収まらないので .above にフォールバック
    #expect(result.direction == .above)
}

@Test func testFrameNearCursorHysteresisFallsBackFromAbove() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 200, height: 252)
    )
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 800, height: 600)
    )
    // カーソルが画面上端付近 → 上には収まらない
    let cursorLocation = WindowPositioning.Point(x: 100, y: 570)
    let desiredSize = WindowPositioning.Size(width: 200, height: 252)

    let result = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize,
        preferredDirection: .above
    )
    // 上に収まらないので .below にフォールバック
    #expect(result.direction == .below)
}

@Test func testFrameNearCursorVerticalClampBottom() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 200, height: 100)
    )
    // Dock等で visibleFrame の下端が50
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 50),
        size: .init(width: 800, height: 550)
    )
    // カーソルが画面下端付近
    let cursorLocation = WindowPositioning.Point(x: 100, y: 100)
    let desiredSize = WindowPositioning.Size(width: 200, height: 100)

    let result = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize,
        preferredDirection: nil
    )
    // 下に配置: y = 100 - 100 - 16 = -16 < 50 → above にフォールバック（既存互換ロジック）
    // 上に配置: y = 100 + 16 = 116
    #expect(result.frame.minY >= screenRect.minY)
}

@Test func testFrameNearCursorVerticalClampTop() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 200, height: 80)
    )
    // 小さい画面で上に配置されるが、ウィンドウ上端が画面を超えるケース
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 800, height: 100)
    )
    // カーソルが画面下端付近 → 下に収まらず上に配置
    let cursorLocation = WindowPositioning.Point(x: 100, y: 5)
    let desiredSize = WindowPositioning.Size(width: 200, height: 80)

    let result = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize,
        preferredDirection: nil
    )
    // 下に配置: y = 5 - 80 - 16 = -91 < 0 → above
    // 上に配置: y = 5 + 16 = 21, maxY = 21 + 80 = 101 > 100 → クランプ: y = 20
    #expect(result.direction == .above)
    #expect(result.frame.maxY <= screenRect.maxY)
    #expect(result.frame.origin.y == 20)
}

@Test func testFrameNearCursorLeftEdgeClamp() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 200, height: 100)
    )
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 50, y: 0),
        size: .init(width: 750, height: 600)
    )
    // カーソルが画面左端より左
    let cursorLocation = WindowPositioning.Point(x: 20, y: 300)
    let desiredSize = WindowPositioning.Size(width: 200, height: 100)

    let result = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize,
        preferredDirection: nil
    )
    #expect(result.frame.minX >= screenRect.minX)
    #expect(result.frame.origin.x == 50)
}

@Test func testFrameNearCursorNilDirectionCompatibleWithExisting() async throws {
    // 既存テスト1と同じ条件で PositionResult 版を呼び、同じ結果になることを確認
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

    let result = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize,
        preferredDirection: nil
    )

    let legacyFrame = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize
    )

    #expect(result.frame == legacyFrame)
    #expect(result.direction == .above)
}

@Test func testFrameNearCursorNeitherFitsChoosesLargerSpace() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 200, height: 500)
    )
    // 非常に小さい画面
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 800, height: 200)
    )
    // カーソルが画面中央よりやや上 → 下のスペースが大きい
    let cursorLocation = WindowPositioning.Point(x: 100, y: 120)
    let desiredSize = WindowPositioning.Size(width: 200, height: 500)

    let result = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize,
        preferredDirection: .above
    )
    // 上にも下にも収まらない → スペースが広い方を選択
    // spaceBelow = 120 - 16 - 0 = 104, spaceAbove = 200 - (120 + 16) = 64
    // → below が広い
    #expect(result.direction == .below)
    // 垂直クランプで画面内に収まること
    #expect(result.frame.minY >= screenRect.minY)
}
