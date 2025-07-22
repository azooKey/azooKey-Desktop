import Cocoa
import Core

extension UserAction {
    // この種のコードは複雑にしかならないので、lintを無効にする
    // swiftlint:disable:next cyclomatic_complexity
    static func getUserAction(event: NSEvent, inputLanguage: InputLanguage) -> UserAction {
        // see: https://developer.mozilla.org/ja/docs/Web/API/UI_Events/Keyboard_event_code_values#mac_%E3%81%A7%E3%81%AE%E3%82%B3%E3%83%BC%E3%83%89%E5%80%A4
        let keyMap: (String) -> String = switch inputLanguage {
        case .english: { $0 }
        case .japanese:
            if Config.TypeCommaAndPeriod().value {
                {
                    KeyMap.h2zMap($0)
                        .replacingOccurrences(of: "、", with: "，")
                        .replacingOccurrences(of: "。", with: "．")
                }
            } else {
                KeyMap.h2zMap
            }
        }
        // Diacritic processing
        if event.modifierFlags.contains(.option) && event.modifierFlags.isDisjoint(with: [.command, .control]) {
            if let deadKeyInfo = DeadKeyComposer.deadKeyList[event.keyCode] {
                if event.modifierFlags.contains(.shift) {
                    // Shift + Option: insert diacritical mark only
                    if let directChar = event.characters {
                        return .input(directChar)
                    } else {
                        return .unknown
                    }
                } else {
                    // Option only: begin dead key sequence
                    return .deadKey(deadKeyInfo.deadKeyChar)
                }
            }
        }
        switch event.keyCode {
        case 0x04: // 'H'
            // Ctrl + H is binding for backspace
            if event.modifierFlags.contains(.control) {
                return .backspace
            } else if let text = event.characters, isPrintable(text) {
                return .input(keyMap(text))
            } else {
                return .unknown
            }
        case 0x23: // Control + p
            if event.modifierFlags.contains(.control) {
                return .navigation(.up)
            } else if let text = event.characters, isPrintable(text) {
                return .input(keyMap(text))
            } else {
                return .unknown
            }
        case 0x2E: // Control + m
            if event.modifierFlags.contains(.control) {
                return .enter
            } else if let text = event.characters, isPrintable(text) {
                return .input(keyMap(text))
            } else {
                return .unknown
            }
        case 0x2D: // Control + n
            if event.modifierFlags.contains(.control) {
                return .navigation(.down)
            } else if let text = event.characters, isPrintable(text) {
                return .input(keyMap(text))
            } else {
                return .unknown
            }
        case 0x03: // Control + f
            if event.modifierFlags.contains(.control) {
                return .navigation(.right)
            } else if let text = event.characters, isPrintable(text) {
                return .input(keyMap(text))
            } else {
                return .unknown
            }
        case 0x22: // Control + i
            if event.modifierFlags.contains(.control) {
                return .editSegment(-1)  // Shift segment cursor left
            } else if let text = event.characters, isPrintable(text) {
                return .input(keyMap(text))
            } else {
                return .unknown
            }
        case 0x1F: // Control + o
            if event.modifierFlags.contains(.control) {
                return .editSegment(1)  // Shift segment cursor right
            } else if let text = event.characters, isPrintable(text) {
                return .input(keyMap(text))
            } else {
                return .unknown
            }
        case 0x25: // Control + l
            if event.modifierFlags.contains(.control) {
                return .function(.nine)
            } else if let text = event.characters, isPrintable(text) {
                return .input(keyMap(text))
            } else {
                return .unknown
            }
        case 0x26: // Control + j
            if event.modifierFlags.contains(.control) {
                return .function(.six)
            } else if let text = event.characters, isPrintable(text) {
                return .input(keyMap(text))
            } else {
                return .unknown
            }
        case 0x28: // Control + k
            if event.modifierFlags.contains(.control) {
                return .function(.seven)
            } else if let text = event.characters, isPrintable(text) {
                return .input(keyMap(text))
            } else {
                return .unknown
            }
        case 0x27: // Control + :
            if event.modifierFlags.contains(.control) {
                return .function(.ten)
            } else if let text = event.characters, isPrintable(text) {
                return .input(keyMap(text))
            } else {
                return .unknown
            }
        case 0x29: // Control + ;
            if event.modifierFlags.contains(.control) {
                return .function(.eight)
            } else if let text = event.characters, isPrintable(text) {
                return .input(keyMap(text))
            } else {
                return .unknown
            }
        case 0x01: // Control + s
            if event.modifierFlags.contains(.control) {
                return .suggest
            } else if let text = event.characters, isPrintable(text) {
                return .input(keyMap(text))
            } else {
                return .unknown
            }
        case 36: // Enter
            return .enter
        case 48: // Tab
            return .tab
        case 49: // Space
            switch (Config.TypeHalfSpace().value, event.modifierFlags.contains(.shift)) {
            case (true, true), (false, false):
                // 全角スペース
                return .space(prefersFullWidthWhenInput: true)
            case (true, false), (false, true):
                return .space(prefersFullWidthWhenInput: false)
            }
        case 51: // Delete
            if event.modifierFlags.contains(.control) {
                return .forget
            } else {
                return .backspace
            }
        case 53: // Escape
            return .escape
        case 93: // Yen
            switch (Config.TypeBackSlash().value, event.modifierFlags.contains(.shift), event.modifierFlags.contains(.option)) {
            case (_, true, _):
                return .input(keyMap("|"))
            case (true, false, false), (false, false, true):
                return .input(keyMap("\\"))
            case (true, false, true), (false, false, false):
                return .input(keyMap("¥"))
            }
        case 43: // Comma
            if event.modifierFlags.contains(.shift) {
                if let text = event.characters, isPrintable(text) {
                    return .input(keyMap(text))
                } else {
                    return .unknown
                }
            } else {
                return .input(keyMap(","))
            }
        case 47: // Period
            if event.modifierFlags.contains(.shift) {
                if let text = event.characters, isPrintable(text) {
                    return .input(keyMap(text))
                } else {
                    return .unknown
                }
            } else {
                return .input(keyMap("."))
            }
        case 97: // F6
            return .function(.six)
        case 98: // F7
            return .function(.seven)
        case 100: // F8
            return .function(.eight)
        case 101: // F9
            return .function(.nine)
        case 109: // F10
            return .function(.ten)
        case 102: // Lang2/kVK_JIS_Eisu
            return .英数
        case 104: // Lang1/kVK_JIS_Kana
            return .かな
        case 123: // Left
            return .navigation(.left)
        case 124: // Right
            return .navigation(.right)
        case 125: // Down
            return .navigation(.down)
        case 126: // Up
            return .navigation(.up)
        case 18, 19, 20, 21, 23, 22, 26, 28, 25, 29:
            if !event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.option) {
                let number: UserAction.Number = [
                    18: .one,
                    19: .two,
                    20: .three,
                    21: .four,
                    23: .five,
                    22: .six,
                    26: .seven,
                    28: .eight,
                    25: .nine,
                    29: .zero
                ][event.keyCode]!
                return .number(number)
            } else {
                // go default
                fallthrough
            }
        default:
            if let text = event.characters, isPrintable(text) {
                return .input(keyMap(text))
            } else {
                return .unknown
            }
        }
    }

    private static func isPrintable(_ text: String) -> Bool {
        let printable: CharacterSet = [.alphanumerics, .symbols, .punctuationCharacters]
            .reduce(into: CharacterSet()) {
                $0.formUnion($1)
            }
        return CharacterSet(text.unicodeScalars).isSubset(of: printable)
    }
}
