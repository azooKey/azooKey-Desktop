import Core
import XCTest

@MainActor
final class ThinClientInputPipelineTests: XCTestCase {
    func testDelayedServerReplyKeepsFollowingInputOwnedAndOrdered() async {
        let printable = KeyEventCore(
            modifierFlags: [],
            characters: "a",
            charactersIgnoringModifiers: "a",
            keyCode: 0
        )
        XCTAssertEqual(
            ConverterClientEventRouter.disposition(
                event: printable,
                context: .init(typeBackSlash: true)
            ),
            .sendToServer
        )

        let backspace = KeyEventCore(
            modifierFlags: [],
            characters: "\u{7f}",
            charactersIgnoringModifiers: "\u{7f}",
            keyCode: 51
        )
        XCTAssertEqual(
            ConverterClientEventRouter.disposition(
                event: backspace,
                context: .init(hasPendingKeyEvents: true, typeBackSlash: true)
            ),
            .sendToServer,
            "未応答中の状態mirrorを信じてbackspaceをapplicationへ漏らしてはいけない"
        )

        let queue = OrderedAsyncCommandQueue<Int>()
        var firstFinish: OrderedAsyncCommandQueue<Int>.Finish?
        var starts: [Int] = []
        var completions: [Int] = []
        let completed = expectation(description: "both key events completed")
        completed.expectedFulfillmentCount = 2

        queue.enqueue(
            operation: { finish in
                starts.append(1)
                firstFinish = finish
            },
            completion: { value in
                completions.append(value)
                completed.fulfill()
            }
        )
        queue.enqueue(
            operation: { finish in
                starts.append(2)
                finish(.finish(2))
            },
            completion: { value in
                completions.append(value)
                completed.fulfill()
            }
        )

        XCTAssertEqual(starts, [1], "2件目は1件目の遅延応答より先にServerへ送ってはいけない")
        firstFinish?(.finish(1))
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(starts, [1, 2])
        XCTAssertEqual(completions, [1, 2])
    }

    func testCommandShortcutFallsThroughEvenWhileServerReplyIsPending() {
        let commandA = KeyEventCore(
            modifierFlags: [.command],
            characters: "a",
            charactersIgnoringModifiers: "a",
            keyCode: 0
        )
        XCTAssertEqual(
            ConverterClientEventRouter.disposition(
                event: commandA,
                context: .init(
                    acknowledgedInputState: .composing,
                    hasPendingKeyEvents: true,
                    typeBackSlash: true
                )
            ),
            .fallthroughToApplication
        )
    }
}
