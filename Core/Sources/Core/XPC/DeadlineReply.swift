import Foundation

/// 別キューから届く応答を期限付きで待つ。期限後の応答は採用しない。
public final class DeadlineReply<Value: Sendable>: @unchecked Sendable {
    private enum State {
        case waiting
        case completed(Value)
        case timedOut
    }

    public let deadline: DispatchTime
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var state: State = .waiting

    public init(timeout: TimeInterval) {
        self.deadline = .now() + max(0, timeout)
    }

    @discardableResult
    public func complete(_ value: Value) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .waiting = state else {
            return false
        }
        guard DispatchTime.now() < deadline else {
            state = .timedOut
            semaphore.signal()
            return false
        }
        state = .completed(value)
        semaphore.signal()
        return true
    }

    /// メインキューを回さず待つ。complete は待機中のキューとは別のキューから呼ぶこと。
    public func wait() -> Value? {
        _ = semaphore.wait(timeout: deadline)
        lock.lock()
        defer { lock.unlock() }
        if case .completed(let value) = state {
            return value
        }
        state = .timedOut
        return nil
    }
}
