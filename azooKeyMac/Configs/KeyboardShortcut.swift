import Cocoa
import Core

/// NSEvent.ModifierFlagsとの相互変換
extension EventModifierFlags {
    public init(from nsModifiers: NSEvent.ModifierFlags) {
        // サポートするモディファイア（control, option, shift, command）のみを抽出
        let supportedMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        self.init(rawValue: nsModifiers.intersection(supportedMask).rawValue)
    }

    public var nsModifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: rawValue)
    }
}
