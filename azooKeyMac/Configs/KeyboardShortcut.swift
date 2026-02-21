import Cocoa
import Core

/// NSEvent.ModifierFlagsとの相互変換
extension EventModifierFlags {
    public init(from nsModifiers: NSEvent.ModifierFlags) {
        // deviceIndependentFlagsMaskを適用してデバイス固有のフラグを除去し、
        // サポートするモディファイア（control, option, shift, command）のみを抽出
        let deviceIndependent = nsModifiers.intersection(.deviceIndependentFlagsMask)
        let supportedMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        self.init(rawValue: deviceIndependent.intersection(supportedMask).rawValue)
    }

    public var nsModifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: rawValue)
    }
}
