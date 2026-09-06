/// Client が決める入力モードと、Server の再初期化が必要かだけを保持する。
/// activation の値を保存しない。送信直前のモード・設定から作ることで、
/// activate → モード変更 → 最初のキー、の順でも古いモードへ戻らない。
public struct ConverterClientSessionState: Sendable {
    public var inputLanguage: InputLanguage = .japanese
    public private(set) var isActive = false
    public private(set) var needsActivation = true

    public init() {}

    public mutating func activate() {
        isActive = true
        needsActivation = true
    }

    public mutating func deactivate() {
        isActive = false
        needsActivation = true
    }

    public mutating func connectionDidReset() {
        needsActivation = true
    }

    public mutating func takeActivation(config: @autoclosure () -> ConverterSessionConfig) -> ConverterSessionActivation? {
        guard needsActivation else {
            return nil
        }
        needsActivation = false
        return .init(config: config(), inputLanguage: inputLanguage)
    }
}
