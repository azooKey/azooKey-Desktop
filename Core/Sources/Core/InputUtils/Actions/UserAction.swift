import Foundation
import KanaKanjiConverterModule

public enum UserAction {
    case input([InputPiece])
    case backspace
    case enter
    case space(prefersFullWidthWhenInput: Bool)
    case escape
    case tab
    case unknown
    case かな
    case 英数
    case navigation(NavigationDirection)
    case function(Function)
    case number(Number)
    case editSegment(Int)
    case suggest
    case forget
    case transformSelectedText
    case deadKey(String)
    case startUnicodeInput

    public enum NavigationDirection: Sendable, Equatable, Hashable {
        case up, down, right, left
    }

    public enum Function: Sendable, Equatable, Hashable {
        case six, seven, eight, nine, ten
    }

    public enum Number: Sendable, Equatable, Hashable {
        case one, two, three, four, five, six, seven, eight, nine, zero, shiftZero
        public var intValue: Int {
            switch self {
            case .one: 1
            case .two: 2
            case .three: 3
            case .four: 4
            case .five: 5
            case .six: 6
            case .seven: 7
            case .eight: 8
            case .nine: 9
            case .zero: 0
            case .shiftZero: 0
            }
        }

        private var currentLayout: Config.KeyboardLayout.Value {
            return Config.KeyboardLayout().value
        }

        public var inputPiece: InputPiece {
            switch currentLayout {
            case .programmerDvorakJIS, .programmerDvorakUS:
                switch self {
                case .one: return .character("&")
                case .two: return .character("[")
                case .three: return .character("{")
                case .four: return .character("}")
                case .five: return .character("(")
                case .six: return .character("=")
                case .seven: return .character("*")
                case .eight: return .character(")")
                case .nine: return .character("+")
                case .zero: return .character("]")
                case .shiftZero: return .key(intention: "6", input: "6", modifiers: [.shift])
                }
            default:
                switch self {
                case .one: return .character("1"); case .two: return .character("2")
                case .three: return .character("3"); case .four: return .character("4")
                case .five: return .character("5"); case .six: return .character("6")
                case .seven: return .character("7"); case .eight: return .character("8")
                case .nine: return .character("9"); case .zero: return .character("0")
                case .shiftZero: return .key(intention: "0", input: "0", modifiers: [.shift])
                }
            }
        }

        public var inputString: String {
            switch currentLayout {
            case .programmerDvorakJIS, .programmerDvorakUS:
                switch self {
                case .one: "&"
                case .two: "["
                case .three: "{"
                case .four: "}"
                case .five: "("
                case .six: "="
                case .seven: "*"
                case .eight: ")"
                case .nine: "+"
                case .zero: "]"
                case .shiftZero: "6"
           }
            default:
                switch self {
                case .one: "1"
                case .two: "2"
                case .three: "3"
                case .four: "4"
                case .five: "5"
                case .six: "6"
                case .seven: "7"
                case .eight: "8"
                case .nine: "9"
                case .zero: "0"
                case .shiftZero: "0"
                }
            }
        }
    }

    private static func intention(_ c: Character, invertPunctuation: Bool) -> Character? {
        switch c {
        case ",":
            let normal: Character = switch Config.PunctuationStyle().value {
            case .kutenAndComma, .periodAndComma: "，"
            default: KeyMap.h2zMap(c) ?? "、"
            }
            if invertPunctuation {
                return normal == "，" ? "、" : "，"
            }
            return normal
        case ".":
            let normal: Character = switch Config.PunctuationStyle().value {
            case .periodAndToten, .periodAndComma: "．"
            default: KeyMap.h2zMap(c) ?? "。"
            }
            if invertPunctuation {
                return normal == "．" ? "。" : "．"
            }
            return normal
        default:
            return KeyMap.h2zMap(c)
        }
    }
    // この種のコードは複雑にしかならないので、lintを無効にする
    // swiftlint:disable:next cyclomatic_complexity
    public static func getUserAction(
        eventCore: KeyEventCore,
        inputLanguage: InputLanguage,
        typeBackSlash: Bool? = nil
    ) -> UserAction {
        let typeBackSlash = typeBackSlash ?? Config.TypeBackSlash().value
        // see: https://developer.mozilla.org/ja/docs/Web/API/UI_Events/Keyboard_event_code_values#mac_%E3%81%A7%E3%81%AE%E3%82%B3%E3%83%BC%E3%83%89%E5%80%A4
        let currentLayout = Config.KeyboardLayout().value
        func keyMap(_ string: String, invertPunctuation: Bool = false) -> [InputPiece] {
            switch inputLanguage {
            case .english:
                return string.map { .character($0) }
            case .japanese:
                return string.map {
                    .key(intention: intention($0, invertPunctuation: invertPunctuation), input: $0, modifiers: [])
                }
            }
        }

        // Resolve action based on logical key character (ignoring modifiers)
        if let originalLogicalKey = eventCore.charactersIgnoringModifiers?.lowercased() {
            let logicalKey: String
            if let firstChar = originalLogicalKey.first, let mappedChar = currentLayout.keyRemapTable?[firstChar] {
                logicalKey = String(mappedChar).lowercased()
            } else {
                logicalKey = originalLogicalKey
            }
            switch (logicalKey, eventCore.modifierFlags) {
            case (let key, [.option])
                where DiacriticAttacher.deadKeyList.contains(key) && inputLanguage == .english:
                return .deadKey(key)

            case ("h", [.control]): // Control + h
                return .backspace
            case ("p", [.control]): // Control + p
                return .navigation(.up)
            case ("m", [.control]): // Control + m
                return .enter
            case ("n", [.control]): // Control + n
                return .navigation(.down)
            case ("f", [.control]): // Control + f
                return .navigation(.right)
            case ("i", [.control]): // Control + i
                return .editSegment(-1)  // Shift segment cursor left
            case ("o", [.control]): // Control + o
                return .editSegment(1)  // Shift segment cursor right
            case ("l", [.control]): // Control + l
                return .function(.nine)
            case ("j", [.control]): // Control + j
                return .function(.six)
            case ("k", [.control]): // Control + k
                return .function(.seven)
            case (";", [.control]): // Control + ;
                return .function(.eight)
            case (":", [.control]): // Control + :
                return .function(.ten)
            case ("'", [.control]): // Control + '
                return .function(.ten)
            case ("s", [.control]): // Control + s
                return .suggest
            case ("u", [.control, .shift]): // Shift + Control + u
                return .startUnicodeInput

            case ("¥", [.shift, .option]), ("¥", [.shift]), ("\\", [.shift, .option]), ("\\", [.shift]):
                if currentLayout.keyRemapTable != nil { break }
                return .input(keyMap("|"))
            case ("¥", []), ("\\", []):
                if currentLayout.hasDistinctBackSlashAndYen {
                    // 「¥」と「\」が両方存在する場合は、
                    // typeBackSlash設定がONの時のみ「¥」「\」のキーを入れ替える
                    let isYen = (logicalKey == "¥")
                    return typeBackSlash ? .input(keyMap(isYen ? "\\" : "¥")) : .input(keyMap(isYen ? "¥" : "\\"))
                } else {
                    // typeBackSlash設定がONの場合は「\」 OFFの場合は「¥」
                    return typeBackSlash ? .input(keyMap("\\")) : .input(keyMap("¥"))
                }

            case ("¥", [.option]), ("\\", [.option]):
                if currentLayout.hasDistinctBackSlashAndYen {
                    // Option押下時は標準の挙動に合わせてUnshifted時と出力を逆転させる。
                    // typeBackSlash設定がOFFの時のみ「¥」「\」のキーを入れ替える
                    let isYen = (logicalKey == "¥")
                    return typeBackSlash ? .input(keyMap(isYen ? "¥" : "\\")) : .input(keyMap(isYen ? "\\" : "¥"))
                } else {
                    // typeBackSlash設定がONの場合は「¥」 OFFの場合は「\」
                    return typeBackSlash ? .input(keyMap("¥")) : .input(keyMap("\\"))
                }

            case ("/", [.shift, .option]) where inputLanguage == .japanese:
                return .input(keyMap("…"))
            case ("/", [.shift]) where inputLanguage == .japanese:
                return .input(keyMap("?"))
            case ("/", [.option]) where inputLanguage == .japanese:
                return .input(keyMap("／"))
            case ("[", [.option]) where inputLanguage == .japanese:
                return .input(keyMap("［"))
            case ("[", [.shift, .option]) where inputLanguage == .japanese:
                return .input(keyMap("｛"))
            case ("]", [.option]) where inputLanguage == .japanese:
                return .input(keyMap("］"))
            case ("]", [.shift, .option]) where inputLanguage == .japanese:
                return .input(keyMap("｝"))
            case (",", [.option]) where inputLanguage == .japanese:
                return .input(keyMap(",", invertPunctuation: true))
            case (".", [.option]) where inputLanguage == .japanese:
                return .input(keyMap(".", invertPunctuation: true))
            default:
                break
            }
        }

        if eventCore.modifierFlags.contains(.control), eventCore.keyCode != 51 {
            // logicalKeyで既知のControlショートカットを処理した後、
            // 後続の物理キー処理をする前に未定義のControl系をホストアプリへ渡す
            // Ctrl+Delete(keyCode 51)だけは.forgetとして下のDelete分岐で扱う
            return .unknown
        }

        if eventCore.keyCode == 29, let text = currentLayout.jisZeroKeyOutput(isShiftPressed:eventCore.modifierFlags.contains(.shift)) {
            // 29番キー(JIS ゼロ)のオーバーライド処理
            // OS仕様(シフト有無によらず常に「0」)を回避し、対象配列のみ出力を上書きする。
            // switch内の fallthrough (case 18...29) との干渉を避け、
            // 対象外の配列を安全にdefaultへ流すためswitch手前でフックする。
            return .input(keyMap(text))
        }

        if eventCore.keyCode == 94, let text = currentLayout.jisUnderscoreKeyOutput(
            isShiftPressed: eventCore.modifierFlags.contains(.shift),
            isOptionPressed: eventCore.modifierFlags.contains(.option),
            typeBackSlash: typeBackSlash
        ) {
            // 94番キー(JIS アンダースコア)のオーバーライド処理
            // OS仕様(シフト有無によらず常に「_」)を回避し、対象配列のみ出力を上書きする。
            // switch内の fallthrough (case 18...29) との干渉を避け、
            // 対象外の配列を安全にdefaultへ流すためswitch手前でフックする。
            return .input(keyMap(text))
        }

        // Resolve action based on physical key code
        switch eventCore.keyCode {
        case 0x24, 0x4C: // Enter (0x24) and Numpad Enter (0x4C)
            return .enter
        case 48: // Tab
            return .tab
        case 49: // Space
            switch (Config.TypeHalfSpace().value, eventCore.modifierFlags.contains(.shift)) {
            case (true, true), (false, false):
                // 全角スペース
                return .space(prefersFullWidthWhenInput: true)
            case (true, false), (false, true):
                return .space(prefersFullWidthWhenInput: false)
            }
        case 51: // Delete
            if eventCore.modifierFlags.contains(.control) {
                return .forget
            } else {
                return .backspace
            }
        case 53: // Escape
            return .escape
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
        case 102: // 英数
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
            // Control+数字はアプリやOS側のショートカットとして使われるため、数字入力としない
            // keyCode分岐に入る前に.unknownとして処理されるが、念のためここでも明示的に扱う
            if eventCore.modifierFlags.isDisjoint(with: [.shift, .option, .control]) {
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
                ][eventCore.keyCode]!
                return .number(number)
            } else if eventCore.keyCode == 29 && eventCore.modifierFlags.contains(.shift) && eventCore.characters == "0" {
                // JISキーボードにおいてShift+0の場合は特別な処理になる
                return .number(.shiftZero)
            } else {
                // go default
                fallthrough
            }
        default:
            if let text = eventCore.characters, isPrintable(text) {
                let mappedText: String
                if let remapTable = currentLayout.keyRemapTable {
                    mappedText = String(text.map { remapTable[$0] ?? $0 })
                } else {
                    mappedText = text
                }
                return .input(keyMap(mappedText))
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
