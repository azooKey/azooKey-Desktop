import KanaKanjiConverterModule
public enum UserAction {
    case input([InputPiece])
    case backspace
    case enter
    case space(prefersFullWidthWhenInput: Bool)
    case escape
    case tab
    case unknown
    case 英数
    case かな
    case navigation(NavigationDirection)
    case function(Function)
    case number(Number)
    case editSegment(Int)
    case suggest
    case forget
    case transformSelectedText
    case deadKey(String)

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
}
