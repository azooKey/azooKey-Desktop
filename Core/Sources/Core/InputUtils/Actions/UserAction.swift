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

        public var inputPiece: InputPiece {
            switch self {
            case .one: .character("1")
            case .two: .character("2")
            case .three: .character("3")
            case .four: .character("4")
            case .five: .character("5")
            case .six: .character("6")
            case .seven: .character("7")
            case .eight: .character("8")
            case .nine: .character("9")
            case .zero: .character("0")
            case .shiftZero: .key(intention: "0", input: "0", modifiers: [.shift])
            }
        }

        public var inputString: String {
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
    public static func getUserAction(eventCore: KeyEventCore, inputLanguage: InputLanguage) -> UserAction {
        // see: https://developer.mozilla.org/ja/docs/Web/API/UI_Events/Keyboard_event_code_values#mac_%E3%81%A7%E3%81%AE%E3%82%B3%E3%83%BC%E3%83%89%E5%80%A4
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
        if let logicalKey = eventCore.charactersIgnoringModifiers?.lowercased() {
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
                return .input(keyMap("|"))
            case ("¥", []), ("\\", []):
                return if Config.TypeBackSlash().value {
                    .input(keyMap("\\"))
                } else {
                    .input(keyMap("¥"))
                }
            case ("¥", [.option]), ("\\", [.option]):
                return if Config.TypeBackSlash().value {
                    .input(keyMap("¥"))
                } else {
                    .input(keyMap("\\"))
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
            if !eventCore.modifierFlags.contains(.shift) && !eventCore.modifierFlags.contains(.option) {
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
