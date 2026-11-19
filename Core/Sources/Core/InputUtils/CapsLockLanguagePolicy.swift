import Foundation

/// Caps Lockの物理状態を、選択中の日本語入力ソースの内部言語へ対応づける。
public enum CapsLockLanguagePolicy {
    public static func language(
        capsLockOn: Bool,
        behavior: Config.CapsLockBehavior.Value
    ) -> InputLanguage? {
        switch behavior {
        case .capsLock:
            // Why not: デフォルトではCaps Lockを言語切替に流用しない。
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

        // Why: 「オフのとき英字」ではCaps ONで日本語入力となるため、
        // 日本語ローマ字入力にも大文字化の解除が必要。
        let shift = event.modifierFlags.contains(.shift)
        return .init(
            modifierFlags: event.modifierFlags,
            characters: event.characters.map { normalizeASCIILetters($0, upper: shift) },
            charactersIgnoringModifiers: event.charactersIgnoringModifiers.map { normalizeASCIILetters($0, upper: false) },
            keyCode: event.keyCode
        )
    }

    private static func normalizeASCIILetters(_ text: String, upper: Bool) -> String {
        // Why not: lowercased()/uppercased() は非ASCII・文字数を変え得る。
        // 記号やレイアウト固有文字はIMEに届いたまま保持する。
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
