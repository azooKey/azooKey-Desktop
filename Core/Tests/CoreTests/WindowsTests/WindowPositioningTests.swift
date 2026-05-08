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

// メインの左側にある副ディスプレイ（origin.x が負）でも、カーソル付近の自然な位置に
// ウィンドウが置かれること。負の origin を持つ screenRect でも minX/maxX/minY/maxY の
// 演算が破綻しないことの回帰テスト。
@Test func testFrameNearCursorPlacesNearCursorOnSecondaryScreenWithNegativeOrigin() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 40, height: 20)
    )
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: -1920, y: 0),
        size: .init(width: 1920, height: 1080)
    )
    // 副ディスプレイ中央付近のカーソル
    let cursorLocation = WindowPositioning.Point(x: -1000, y: 500)
    let desiredSize = WindowPositioning.Size(width: 40, height: 30)

    let frame = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize
    )

    // 上方向配置: origin.y = 500 - 30 - 16 = 454
    #expect(frame.origin == WindowPositioning.Point(x: -1000, y: 454))
    #expect(frame.size == desiredSize)
    #expect(frame.minX >= screenRect.minX)
    #expect(frame.maxX <= screenRect.maxX)
}

// ウィンドウがスクリーンより広い場合、右端クランプで origin.x が screenRect.minX より
// 左に押し出されないこと（左端クランプの追加検証）。
@Test func testFrameNearCursorClampsToLeftEdgeWhenWindowWiderThanScreen() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 60, height: 30)
    )
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 50, height: 100)
    )
    let cursorLocation = WindowPositioning.Point(x: 40, y: 50)
    let desiredSize = WindowPositioning.Size(width: 60, height: 30)

    let frame = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize
    )

    // 右端クランプで origin.x = 50 - 60 = -10 になるが、左端クランプで minX に張り付く。
    #expect(frame.origin.x == screenRect.minX)
}

// macOS は y up 座標系で minY が画面の下端。
// 上方向配置（カーソル上にウィンドウを置く分岐）でも minY < screenRect.minY なら
// minY（=画面下端）に張り付くこと。cursorHeight 分だけ画面下端を割り込むケースを再現。
@Test func testFrameNearCursorClampsToBottomEdgeWhenAbovePlacementOverflows() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 20, height: 30)
    )
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 100, height: 100)
    )
    // cursorY - height = 0 (= minY) なので「>= minY」で上方向配置になる。
    // origin.y = 30 - 30 - 16 = -16 となり minY を割り込む。
    let cursorLocation = WindowPositioning.Point(x: 50, y: 30)
    let desiredSize = WindowPositioning.Size(width: 20, height: 30)

    let frame = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize
    )

    #expect(frame.minY == screenRect.minY)
}

// 上端クランプ: ウィンドウが screenRect より縦に大きい場合、まず maxY 側で
// 画面上端に張り付こうとし、それでも minY < screenRect.minY なら最終的に minY=下端に
// 寄る。ここではまず maxY > screenRect.maxY を踏ませることが目的。
@Test func testFrameNearCursorClampsToTopEdgeWhenWindowTallerThanScreen() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 20, height: 200)
    )
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 100, height: 100)
    )
    // cursorY - height = -190 < 0 なので下方向配置。origin.y = 10 + 16 = 26、
    // maxY = 226 > 100 で maxY クランプが発動する。
    let cursorLocation = WindowPositioning.Point(x: 50, y: 10)
    let desiredSize = WindowPositioning.Size(width: 20, height: 200)

    let frame = WindowPositioning.frameNearCursor(
        currentFrame: currentFrame,
        screenRect: screenRect,
        cursorLocation: cursorLocation,
        desiredSize: desiredSize
    )

    // maxY クランプ: origin.y = 100 - 200 = -100。直後の minY クランプで 0 へ補正される。
    #expect(frame.minY == screenRect.minY)
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

// 副ディスプレイがメインの左にある（origin.x が負）想定で、anchor も負座標にある場合に
// frameRightOfAnchor が破綻せず副ディスプレイ内へ収まること。
// 予測ウィンドウの位置決め (positionPredictionWindowRightOfCandidateWindow) の回帰テスト。
@Test func testFrameRightOfAnchorOnSecondaryScreenWithNegativeOrigin() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 200, height: 100)
    )
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: -1920, y: 0),
        size: .init(width: 1920, height: 1080)
    )
    // 副ディスプレイ中央付近の anchor。右隣に gap=8 で十分余地あり。
    let anchorFrame = WindowPositioning.Rect(
        origin: .init(x: -1000, y: 500),
        size: .init(width: 300, height: 200)
    )

    let frame = WindowPositioning.frameRightOfAnchor(
        currentFrame: currentFrame,
        anchorFrame: anchorFrame,
        screenRect: screenRect,
        gap: 8
    )

    #expect(frame.origin.x == anchorFrame.maxX + 8) // = -692
    #expect(frame.origin.y == anchorFrame.origin.y) // = 500
    #expect(frame.size == currentFrame.size)
    #expect(frame.minX >= screenRect.minX)
    #expect(frame.maxX <= screenRect.maxX)
}

// 副ディスプレイ右端ぎりぎりに anchor がある場合、右隣に置けないので
// 左へクランプされ、結果として screenRect 内に収まること（副ディスプレイ側で発動）。
@Test func testFrameRightOfAnchorClampsLeftWithinSecondaryScreen() async throws {
    let currentFrame = WindowPositioning.Rect(
        origin: .init(x: 0, y: 0),
        size: .init(width: 200, height: 100)
    )
    let screenRect = WindowPositioning.Rect(
        origin: .init(x: -1920, y: 0),
        size: .init(width: 1920, height: 1080)
    )
    // anchor.maxX = -50。+gap=8 で予測ウィンドウは -42 始まりとなり、maxX = 158 で
    // 副ディスプレイ右端 (0) を超える。クランプで origin.x = 0 - 200 = -200 に補正される。
    let anchorFrame = WindowPositioning.Rect(
        origin: .init(x: -350, y: 100),
        size: .init(width: 300, height: 200)
    )

    let frame = WindowPositioning.frameRightOfAnchor(
        currentFrame: currentFrame,
        anchorFrame: anchorFrame,
        screenRect: screenRect,
        gap: 8
    )

    #expect(frame.origin.x == screenRect.maxX - currentFrame.width)
    #expect(frame.maxX <= screenRect.maxX)
    #expect(frame.minX >= screenRect.minX)
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
