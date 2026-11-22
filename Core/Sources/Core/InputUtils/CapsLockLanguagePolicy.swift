import Foundation

/// Caps Lockの物理状態を、既存のJapanese/Roman入力モードへ対応づける。
public enum CapsLockLanguagePolicy {
    /// A normal keyDown must not undo an explicitly selected Japanese/Roman mode.
    /// Only a Caps key event or a missed change in its physical state switches modes.
    public static func shouldSwitch(
        previousCapsLockOn: Bool?,
        capsLockOn: Bool,
        isCapsLockEvent: Bool
    ) -> Bool {
        isCapsLockEvent || (previousCapsLockOn.map { $0 != capsLockOn } ?? false)
    }

    public static func language(
        capsLockOn: Bool,
        behavior: Config.CapsLockBehavior.Value
    ) -> InputLanguage? {
        switch behavior {
        case .capsLock:
            return nil
        case .englishWhenOn:
            return capsLockOn ? .english : .japanese
        case .englishWhenOff:
            return capsLockOn ? .japanese : .english
        }
    }

    /// Caps Lock中の英字大文字化を除去する。Shiftのみが大文字を決める。
    public static func normalizedEvent(
        _ event: KeyEventCore,
        capsLockOn: Bool,
        behavior: Config.CapsLockBehavior.Value
    ) -> KeyEventCore {
        guard capsLockOn, behavior != .capsLock else {
            return event
        }

        // Caps ONで日本語入力する設定でも、ローマ字を大文字のまま渡さない。
        let shift = event.modifierFlags.contains(.shift)
        return .init(
            modifierFlags: event.modifierFlags,
            characters: event.characters.map { normalizeASCIILetters($0, upper: shift) },
            charactersIgnoringModifiers: event.charactersIgnoringModifiers.map { normalizeASCIILetters($0, upper: false) },
            keyCode: event.keyCode
        )
    }

    private static func normalizeASCIILetters(_ text: String, upper: Bool) -> String {
        // 非ASCII文字やレイアウト固有の記号は変更しない。
        text.unicodeScalars.map { scalar -> String in
            switch scalar.value {
            case 65...90:
                return String(UnicodeScalar(upper ? scalar.value : scalar.value + 32)!)
            case 97...122:
                return String(UnicodeScalar(upper ? scalar.value - 32 : scalar.value)!)
            default:
                return String(scalar)
            }
        }.joined()
    }
}
