import Core
import Testing

@Test func clientMarkedTextTrackerSkipsEmptyMarkedTextWhenNothingIsMarked() {
    let tracker = ClientMarkedTextTracker()
    // 入力を始める前は、空の未確定文字列を送る必要はない
    #expect(!tracker.shouldSendMarkedText(markedTextIsEmpty: true))
    #expect(tracker.shouldSendMarkedText(markedTextIsEmpty: false))
}

@Test func clientMarkedTextTrackerSkipsEmptyMarkedTextAfterCommit() {
    var tracker = ClientMarkedTextTracker()
    tracker.didSendMarkedText(markedTextIsEmpty: false)
    #expect(tracker.clientHasMarkedText)

    // 確定するとアプリ側の未確定文字列はなくなるので、空の setMarkedText は送らない
    tracker.didInsertText()
    #expect(!tracker.clientHasMarkedText)
    #expect(!tracker.shouldSendMarkedText(markedTextIsEmpty: true))
}

@Test func clientMarkedTextTrackerClearsMarkedTextWhenCompositionIsCancelled() {
    var tracker = ClientMarkedTextTracker()
    tracker.didSendMarkedText(markedTextIsEmpty: false)

    // 確定せずに入力を取り消した（BackSpace で全部消したなど）ときは、表示を消すために送る
    #expect(tracker.shouldSendMarkedText(markedTextIsEmpty: true))
    tracker.didSendMarkedText(markedTextIsEmpty: true)
    #expect(!tracker.clientHasMarkedText)
    #expect(!tracker.shouldSendMarkedText(markedTextIsEmpty: true))
}

@Test func clientMarkedTextTrackerSendsRemainingTextAfterPartialCommit() {
    var tracker = ClientMarkedTextTracker()
    tracker.didSendMarkedText(markedTextIsEmpty: false)

    // 文節の一部だけを確定した場合、残りの未確定文字列は送る
    tracker.didInsertText()
    #expect(tracker.shouldSendMarkedText(markedTextIsEmpty: false))
    tracker.didSendMarkedText(markedTextIsEmpty: false)
    #expect(tracker.clientHasMarkedText)
}
