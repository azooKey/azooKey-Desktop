public enum UserAction {
    case input(String)
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

    public enum NavigationDirection: Sendable, Equatable, Hashable {
        case up, down, right, left
    }

    public enum Function: Sendable, Equatable, Hashable {
        case six, seven, eight
    }

    public enum Number: Sendable, Equatable, Hashable {
        case one, two, three, four, five, six, seven, eight, nine, zero
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
            }
        }
    }
}
