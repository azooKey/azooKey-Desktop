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
    }

    private var entries: [Entry] = []
    private var isRunning = false
    private let scheduleRetry: (@escaping @MainActor @Sendable () -> Void) -> Void

    public init(
        scheduleRetry: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void = { action in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                action()
            }
        }
    ) {
        self.scheduleRetry = scheduleRetry
    }

    @MainActor public var count: Int {
        entries.count
    }

    @MainActor public func enqueue(
        operation: @escaping Operation,
        completion: @escaping @MainActor (Value) -> Void
    ) {
        entries.append(Entry(operation: operation, completion: completion))
        startNextIfNeeded()
    }

    @MainActor private func startNextIfNeeded() {
        guard !isRunning, let entry = entries.first else {
            return
        }
        isRunning = true
        entry.operation { [weak self] outcome in
            guard let self else {
                return
            }
            switch outcome {
            case .finish(let value):
                self.entries.removeFirst()
                self.isRunning = false
                entry.completion(value)
                self.startNextIfNeeded()
            case .retry:
                self.isRunning = false
                self.scheduleRetry { [weak self] in
                    self?.startNextIfNeeded()
                }
            }
        }
    }
}
