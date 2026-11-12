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

    /// 日本語入力で記号キーを押したときに、全角と半角のどちらを入力するかを決める設定
    public struct SymbolWidthOptions: Sendable, Equatable {
        public init(
            typeHalfWidthSymbol: Bool,
            typeHalfWidthSymbolAfterNumber: Bool,
            typeHalfWidthSlash: Bool,
            inputStyle: Config.InputStyle.Value
        ) {
            self.typeHalfWidthSymbol = typeHalfWidthSymbol
            self.typeHalfWidthSymbolAfterNumber = typeHalfWidthSymbolAfterNumber
            self.typeHalfWidthSlash = typeHalfWidthSlash
            self.inputStyle = inputStyle
        }

        /// 「！」「（」などの全角記号の代わりに半角記号を入力する
        public var typeHalfWidthSymbol: Bool
        /// 数字の直後の「.」「,」「:」「/」「-」を半角で入力する
        public var typeHalfWidthSymbolAfterNumber: Bool
        /// 「/」で「・」ではなく「/」を入力する
        public var typeHalfWidthSlash: Bool
        /// 入力方式。入力表が全角記号をキーに使う入力方式では、その記号を半角にしない
        public var inputStyle: Config.InputStyle.Value

        static var current: Self {
            .init(
                typeHalfWidthSymbol: Config.TypeHalfWidthSymbol().value,
                typeHalfWidthSymbolAfterNumber: Config.TypeHalfWidthSymbolAfterNumber().value,
                typeHalfWidthSlash: Config.TypeHalfWidthSlash().value,
                inputStyle: Config.InputStyle().value
            )
        }

        /// 半角記号の設定でも全角のまま入力する、日本語の入力に使う記号（句読点は句読点の種類の設定に従う）
        private static let japanesePunctuation: Set<Character> = ["「", "」", "ー"]

        /// 数字の直後で半角にする記号（3.14、1,000、12:30、11/12、03-1234）
        private static let symbolsAfterNumber: Set<Character> = [".", ",", ":", "/", "-"]

        /// キー `c` で、全角記号 `fullWidth` の代わりに半角記号を入力するかどうか
        func typesHalfWidth(_ c: Character, fullWidth: Character) -> Bool {
            if c == "/" && self.typeHalfWidthSlash {
                return switch self.inputStyle {
                case .default, .defaultAZIK, .custom:
                    true
                case .defaultKanaJIS, .defaultKanaUS:
                    // かな入力では「/」のキーで「め」を入力する
                    false
                }
            }
            guard self.typeHalfWidthSymbol, !Self.japanesePunctuation.contains(fullWidth) else {
                return false
            }
            return switch self.inputStyle {
            case .default:
                true
            case .defaultAZIK:
                // AZIKでは「;」で「っ」、「:」で「ー」を入力する
                fullWidth != "；" && fullWidth != "："
            case .defaultKanaJIS, .defaultKanaUS, .custom:
                // かな入力では記号キーでかなを入力する。カスタムの入力表も全角記号をキーに使うことがある
                false
            }
        }

        /// 直前の文字 `precedingCharacter` に続く記号 `c` を半角で入力するかどうか
        func typesHalfWidth(_ c: Character, after precedingCharacter: Character?) -> Bool {
            guard self.typeHalfWidthSymbolAfterNumber,
                  Self.symbolsAfterNumber.contains(c),
                  let precedingCharacter,
                  precedingCharacter.isASCII,
                  precedingCharacter.isNumber else {
                return false
            }
            return switch self.inputStyle {
            case .default, .defaultAZIK, .custom:
                true
            case .defaultKanaJIS, .defaultKanaUS:
                // かな入力では「,」「.」「:」「/」「-」のキーでかなを入力する
                false
            }
        }
    }

    private static func intention(
        _ c: Character,
        invertPunctuation: Bool,
        symbolWidth: SymbolWidthOptions,
        precedingCharacter: Character?
    ) -> Character? {
        // Optionキーで句読点を切り替えたときは、その指定を優先する
        if !invertPunctuation && symbolWidth.typesHalfWidth(c, after: precedingCharacter) {
            return c
        }
        switch c {
        case ",", ".":
            return punctuationIntention(c, invertPunctuation: invertPunctuation)
        default:
            guard let fullWidth = KeyMap.h2zMap(c) else {
                return nil
            }
            return symbolWidth.typesHalfWidth(c, fullWidth: fullWidth) ? c : fullWidth
        }
    }

    /// 句読点の種類の設定に合わせて、「,」「.」で入力する全角の句読点を返す
    private static func punctuationIntention(_ c: Character, invertPunctuation: Bool) -> Character? {
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
        typeBackSlash: Bool? = nil,
        symbolWidth: SymbolWidthOptions? = nil,
        precedingCharacter: Character? = nil,
        halfWidthRomanWithControlL: Bool? = nil
    ) -> UserAction {
        let typeBackSlash = typeBackSlash ?? Config.TypeBackSlash().value
        // see: https://developer.mozilla.org/ja/docs/Web/API/UI_Events/Keyboard_event_code_values#mac_%E3%81%A7%E3%81%AE%E3%82%B3%E3%83%BC%E3%83%89%E5%80%A4
        func keyMap(_ string: String, invertPunctuation: Bool = false) -> [InputPiece] {
            switch inputLanguage {
            case .english:
                return string.map { .character($0) }
            case .japanese:
                let symbolWidth = symbolWidth ?? .current
                var precedingCharacter = precedingCharacter
                var pieces: [InputPiece] = []
                for c in string {
                    let resolved = intention(
                        c,
                        invertPunctuation: invertPunctuation,
                        symbolWidth: symbolWidth,
                        precedingCharacter: precedingCharacter
                    )
                    pieces.append(.key(intention: resolved, input: c, modifiers: []))
                    precedingCharacter = resolved ?? c
                }
                return pieces
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
                return if halfWidthRomanWithControlL ?? Config.HalfWidthRomanWithControlL().value {
                    .function(.ten)
                } else {
                    .function(.nine)
                }
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
                return if typeBackSlash {
                    .input(keyMap("\\"))
                } else {
                    .input(keyMap("¥"))
                }
            case ("¥", [.option]), ("\\", [.option]):
                return if typeBackSlash {
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

        if eventCore.modifierFlags.contains(.control), eventCore.keyCode != 51 {
            // logicalKeyで既知のControlショートカットを処理した後、
            // 後続の物理キー処理をする前に未定義のControl系をホストアプリへ渡す
            // Ctrl+Delete(keyCode 51)だけは.forgetとして下のDelete分岐で扱う
            return .unknown
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
        case 0x74, 0x79: // Page Up / Page Downは候補選択中のInputStateで処理する
            return .unknown
        case 0x73, 0x77, 0x75, 0x47:
            // Numpadでそれぞれ「入力先頭にカーソルを移動」「入力末尾にカーソルを移動」「順方向削除」「入力全消し（より強いエスケープ）」に対応するが、サポート外の動作として明示的に無効化
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
