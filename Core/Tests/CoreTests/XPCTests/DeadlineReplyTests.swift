import Core
import Foundation
import Testing

@MainActor
@Test func deadlineReplyCanArriveWhileMainActorIsBlocked() {
    let reply = DeadlineReply<String>(timeout: 2)
    DispatchQueue.global().async { reply.complete("response") }
    #expect(reply.wait() == "response")
}

@Test func deadlineReplyTimesOutAndRejectsLateReply() {
    let reply = DeadlineReply<String>(timeout: 0.01)
    #expect(reply.wait() == nil)
    #expect(!reply.complete("late response"))
}

@Test func deadlineReplyDoesNotAcceptResponseAfterDeadlineBeforeWait() {
    let reply = DeadlineReply<String>(timeout: 0)
    #expect(!reply.complete("too late"))
    #expect(reply.wait() == nil)
}

@Test func deadlineReplyOnlyAcceptsFirstCompletion() {
    let reply = DeadlineReply<String>(timeout: 2)
    #expect(reply.complete("first"))
    #expect(!reply.complete("second"))
    #expect(reply.wait() == "first")
}
