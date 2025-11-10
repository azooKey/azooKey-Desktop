import Cocoa
import Core
import KanaKanjiConverterModule

extension UserAction {
    private static func intention(_ c: Character) -> Character? {
        switch c {
        case ",":
            switch Config.PunctuationStyle().value {
            case .kutenAndComma, .periodAndComma: "，"
            default: KeyMap.h2zMap(c)
            }
        case ".":
            switch Config.PunctuationStyle().value {
            case .periodAndToten, .periodAndComma: "．"
            default: KeyMap.h2zMap(c)
            }
        default: KeyMap.h2zMap(c)
        }
    }

    // この種のコードは複雑にしかならないので、lintを無効にする
    // swiftlint:disable:next cyclomatic_complexity
    static func getUserAction(event: NSEvent, inputLanguage: InputLanguage) -> UserAction {
        // see: https://developer.mozilla.org/ja/docs/Web/API/UI_Events/Keyboard_event_code_values#mac_%E3%81%A7%E3%81%AE%E3%82%B3%E3%83%BC%E3%83%89%E5%80%A4
        let keyMap: (String) -> [InputPiece] = switch inputLanguage {
        case .english: { string in string.map { .character($0) } }
        case .japanese:
            { string in
                string.map {
                    .key(intention: intention($0), input: $0, modifiers: [])
                }
            }
        }
        // Diacritic processing
        if event.modifierFlags.contains(.option) && event.modifierFlags.isDisjoint(with: [.command, .control]) {
            if let diacritic = DiacriticAttacher.deadKeyList[event.keyCode] {
                if event.modifierFlags.contains(.shift) {
                    // Shift + Option: insert diacritical mark only
                    return event.characters.map { .input($0.map(InputPiece.character)) } ?? .unknown
                } else {
                    // Option only: begin dead key sequence
                    return .deadKey(diacritic)
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
        case 0x24, 0x4C: // Enter (0x24) and Numpad Enter (0x4C)
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
        case 0x2C: // Slash
            return switch inputLanguage {
            case .japanese:
                if event.modifierFlags.contains([.shift, .option]) {
                    // Option+Shift入力で…を入力する
                    .input(keyMap("…"))
                } else if event.modifierFlags.contains(.shift) {
                    // シフト入力でQuestionを入力する
                    .input(keyMap("?"))
                } else if event.modifierFlags.contains(.option) {
                    // Option入力でSlashを入力する
                    .input(keyMap("／"))
                } else {
                    // そうでない場合は「・」を入力する（"/"がkeyMapで"・"に変換される）
                    .input(keyMap("/"))
                }
            case .english:
                if let text = event.characters, isPrintable(text) {
                    .input(keyMap(text))
                } else {
                    .unknown
                }
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
        case 0x4B: // Numpad Slash
            return .input([.character("/")])
        case 0x5F: // Numpad Comma
            return .input([.character(",")])
        case 0x41: // Numpad Period
            return .input([.character(".")])
        case 0x73, 0x77, 0x74, 0x79, 0x75, 0x47:
            // Numpadでそれぞれ「入力先頭にカーソルを移動」「入力末尾にカーソルを移動」「変換候補欄を1ページ戻る」「変換候補欄を1ページ進む」「順方向削除」「入力全消し（より強いエスケープ）」に対応するが、サポート外の動作として明示的に無効化
            return .unknown
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
            } else if event.keyCode == 29 && event.modifierFlags.contains(.shift) && event.characters == "0" {
                // JISキーボードにおいてShift+0の場合は特別な処理になる
                return .number(.shiftZero)
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
