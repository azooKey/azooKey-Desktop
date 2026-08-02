import Foundation

/// 非同期コマンドを必ず1件ずつ開始し、完了順序を投入順序と一致させるキュー。
///
/// InputMethodKit の `handle` をブロックせずに ConverterServer へイベントを送るために使う。
/// `.retry` では先頭要素を削除しないため、一時的な XPC 切断で入力を失わない。
public final class OrderedAsyncCommandQueue<Value> {
    public enum Outcome {
        case finish(Value)
        case retry
    }

    public typealias Finish = @MainActor (Outcome) -> Void
    public typealias Operation = @MainActor (@escaping Finish) -> Void

    private struct Entry {
        var operation: Operation
        var completion: @MainActor (Value) -> Void
        var timeout: TimeInterval?
        var timeoutOutcome: Outcome?
        var onTimeout: @MainActor () -> Void
    }

    private var entries: [Entry] = []
    private var activeOperationID: UUID?
    private let scheduleRetry: (@escaping @MainActor @Sendable () -> Void) -> Void
    private let scheduleTimeout: (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void

    public init(
        scheduleRetry: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void = { action in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                action()
            }
        },
        scheduleTimeout: @escaping (
            TimeInterval,
            @escaping @MainActor @Sendable () -> Void
        ) -> Void = { timeout, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                action()
            }
        }
    ) {
        self.scheduleRetry = scheduleRetry
        self.scheduleTimeout = scheduleTimeout
    }

    @MainActor public var count: Int {
        entries.count
    }

    @MainActor public func enqueue(
        timeout: TimeInterval? = nil,
        timeoutOutcome: Outcome? = nil,
        onTimeout: @escaping @MainActor () -> Void = {},
        operation: @escaping Operation,
        completion: @escaping @MainActor (Value) -> Void
    ) {
        entries.append(
            Entry(
                operation: operation,
                completion: completion,
                timeout: timeout,
                timeoutOutcome: timeoutOutcome,
                onTimeout: onTimeout
            )
        )
        startNextIfNeeded()
    }

    @MainActor private func startNextIfNeeded() {
        guard activeOperationID == nil, let entry = entries.first else {
            return
        }
        let operationID = UUID()
        activeOperationID = operationID
        entry.operation { [weak self] outcome in
            self?.complete(operationID: operationID, entry: entry, outcome: outcome)
        }
        if let timeout = entry.timeout, let timeoutOutcome = entry.timeoutOutcome {
            scheduleTimeout(timeout) { [weak self] in
                guard let self, self.activeOperationID == operationID else {
                    return
                }
                entry.onTimeout()
                self.complete(operationID: operationID, entry: entry, outcome: timeoutOutcome)
            }
        }
    }

    @MainActor private func complete(
        operationID: UUID,
        entry: Entry,
        outcome: Outcome
    ) {
        guard activeOperationID == operationID else {
            return
        }
        switch outcome {
        case .finish(let value):
            entries.removeFirst()
            activeOperationID = nil
            entry.completion(value)
            startNextIfNeeded()
        case .retry:
            activeOperationID = nil
            scheduleRetry { [weak self] in
                self?.startNextIfNeeded()
            }
        }
    }
}
