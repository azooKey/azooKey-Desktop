import Foundation
import KanaKanjiConverterModule

public enum ConverterServerCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode(_ command: ConverterServerCommand) throws -> Data {
        try encoder.encode(command)
    }

    public static func decodeCommand(from data: Data) throws -> ConverterServerCommand {
        try decoder.decode(ConverterServerCommand.self, from: data)
    }

    public static func encode(_ response: ConverterServerResponse) throws -> Data {
        try encoder.encode(response)
    }

    public static func decodeResponse(from data: Data) throws -> ConverterServerResponse {
        try decoder.decode(ConverterServerResponse.self, from: data)
    }
}

public enum ConverterServerCommand: Codable, Sendable {
    case activate(sessionID: String)
    case deactivate(sessionID: String)
    case snapshot(sessionID: String, inputState: ConverterInputState)
    case stopComposition(sessionID: String)
    case forgetMemory(sessionID: String)
    case handleKeyEvent(sessionID: String, request: ConverterKeyEventRequest)
    case selectCandidate(sessionID: String, index: Int)
    case submitSelectedCandidate(sessionID: String, leftSideContext: String?)
    case commitComposition(sessionID: String, inputState: ConverterInputState)
}

public struct ConverterKeyEventRequest: Codable, Sendable, Equatable {
    public var event: KeyEventCore
    public var inputState: ConverterInputState
    public var inputLanguage: InputLanguage
    public var inputStyle: ConverterInputStyle
    public var liveConversionEnabled: Bool
    public var enableDebugWindow: Bool
    public var enableSuggestion: Bool
    public var enablePredictiveTyping: Bool
    public var enableTypoCorrection: Bool
    public var leftSideContext: String?
    public var visibleCandidateStartIndex: Int

    public init(
        event: KeyEventCore,
        inputState: ConverterInputState,
        inputLanguage: InputLanguage,
        inputStyle: ConverterInputStyle,
        liveConversionEnabled: Bool,
        enableDebugWindow: Bool,
        enableSuggestion: Bool,
        enablePredictiveTyping: Bool = false,
        enableTypoCorrection: Bool = false,
        leftSideContext: String?,
        visibleCandidateStartIndex: Int = 0
    ) {
        self.event = event
        self.inputState = inputState
        self.inputLanguage = inputLanguage
        self.inputStyle = inputStyle
        self.liveConversionEnabled = liveConversionEnabled
        self.enableDebugWindow = enableDebugWindow
        self.enableSuggestion = enableSuggestion
        self.enablePredictiveTyping = enablePredictiveTyping
        self.enableTypoCorrection = enableTypoCorrection
        self.leftSideContext = leftSideContext
        self.visibleCandidateStartIndex = visibleCandidateStartIndex
    }
}

public enum ConverterClientEffect: Codable, Sendable, Equatable {
    case insertText(String)
    case switchInputLanguage(InputLanguage)
    case requestPredictiveSuggestion
    case requestReplaceSuggestion
    case selectNextReplaceSuggestionCandidate
    case selectPreviousReplaceSuggestionCandidate
    case submitReplaceSuggestionCandidate
    case hideReplaceSuggestionWindow
    case showPromptInputWindow
    case transformSelectedText(String, String)
    case fallthroughToApplication
}

public struct ConverterServerResponse: Codable, Sendable {
    public var handled: Bool
    public var effects: [ConverterClientEffect]
    public var inputState: ConverterInputState
    public var inputLanguage: InputLanguage?
    public var snapshot: ConverterSessionSnapshot

    public init(
        handled: Bool = true,
        effects: [ConverterClientEffect] = [],
        inputState: ConverterInputState = .none,
        inputLanguage: InputLanguage? = nil,
        snapshot: ConverterSessionSnapshot
    ) {
        self.handled = handled
        self.effects = effects
        self.inputState = inputState
        self.inputLanguage = inputLanguage
        self.snapshot = snapshot
    }
}

public struct ConverterSessionSnapshot: Codable, Sendable {
    public var markedText: ConverterMarkedText
    public var candidateWindow: ConverterCandidateWindow
    public var predictionCandidates: [ConverterPredictionCandidate]
    public var isEmpty: Bool
    public var convertTarget: String

    public init(
        markedText: ConverterMarkedText,
        candidateWindow: ConverterCandidateWindow,
        predictionCandidates: [ConverterPredictionCandidate] = [],
        isEmpty: Bool,
        convertTarget: String
    ) {
        self.markedText = markedText
        self.candidateWindow = candidateWindow
        self.predictionCandidates = predictionCandidates
        self.isEmpty = isEmpty
        self.convertTarget = convertTarget
    }
}

public extension ConverterSessionSnapshot {
    static var empty: ConverterSessionSnapshot {
        ConverterSessionSnapshot(
            markedText: ConverterMarkedText(
                SegmentsManager.MarkedText(
                    text: [],
                    selectionRange: NSRange(location: NSNotFound, length: NSNotFound)
                )
            ),
            candidateWindow: .hidden,
            isEmpty: true,
            convertTarget: ""
        )
    }
}

public enum ConverterInputState: Codable, Sendable, Equatable {
    case none
    case attachDiacritic(String)
    case composing
    case previewing
    case selecting
    case replaceSuggestion
    case unicodeInput(String)

    public init(_ inputState: InputState) {
        switch inputState {
        case .none:
            self = .none
        case .attachDiacritic(let value):
            self = .attachDiacritic(value)
        case .composing:
            self = .composing
        case .previewing:
            self = .previewing
        case .selecting:
            self = .selecting
        case .replaceSuggestion:
            self = .replaceSuggestion
        case .unicodeInput(let value):
            self = .unicodeInput(value)
        }
    }

    public var inputState: InputState {
        switch self {
        case .none:
            .none
        case .attachDiacritic(let value):
            .attachDiacritic(value)
        case .composing:
            .composing
        case .previewing:
            .previewing
        case .selecting:
            .selecting
        case .replaceSuggestion:
            .replaceSuggestion
        case .unicodeInput(let value):
            .unicodeInput(value)
        }
    }
}

public enum ConverterInputStyle: Codable, Sendable, Equatable {
    case direct
    case roman2kana
    case defaultRomanToKana
    case defaultAZIK
    case defaultKanaUS
    case defaultKanaJIS
    case empty
    case tableName(String)

    public init(_ inputStyle: InputStyle) {
        switch inputStyle {
        case .direct:
            self = .direct
        case .roman2kana:
            self = .roman2kana
        case .mapped(let id):
            switch id {
            case .defaultRomanToKana:
                self = .defaultRomanToKana
            case .defaultAZIK:
                self = .defaultAZIK
            case .defaultKanaUS:
                self = .defaultKanaUS
            case .defaultKanaJIS:
                self = .defaultKanaJIS
            case .empty:
                self = .empty
            case .tableName(let name):
                self = .tableName(name)
            }
        }
    }

    public var inputStyle: InputStyle {
        switch self {
        case .direct:
            .direct
        case .roman2kana:
            .roman2kana
        case .defaultRomanToKana:
            .mapped(id: .defaultRomanToKana)
        case .defaultAZIK:
            .mapped(id: .defaultAZIK)
        case .defaultKanaUS:
            .mapped(id: .defaultKanaUS)
        case .defaultKanaJIS:
            .mapped(id: .defaultKanaJIS)
        case .empty:
            .mapped(id: .empty)
        case .tableName(let name):
            .mapped(id: .tableName(name))
        }
    }
}

public struct ConverterMarkedText: Codable, Sendable, Equatable {
    public var elements: [Element]
    public var selectionRange: ConverterRange

    public init(elements: [Element], selectionRange: ConverterRange) {
        self.elements = elements
        self.selectionRange = selectionRange
    }

    public init(_ markedText: SegmentsManager.MarkedText) {
        self.elements = markedText.map(Element.init)
        self.selectionRange = ConverterRange(markedText.selectionRange)
    }

    public struct Element: Codable, Sendable, Equatable {
        public var content: String
        public var focus: FocusState

        public init(_ element: SegmentsManager.MarkedText.Element) {
            self.content = element.content
            self.focus = FocusState(element.focus)
        }

        public init(content: String, focus: FocusState) {
            self.content = content
            self.focus = focus
        }
    }

    public enum FocusState: Codable, Sendable, Equatable {
        case focused
        case unfocused
        case none

        public init(_ focusState: SegmentsManager.MarkedText.FocusState) {
            switch focusState {
            case .focused:
                self = .focused
            case .unfocused:
                self = .unfocused
            case .none:
                self = .none
            }
        }
    }
}

public struct ConverterRange: Codable, Sendable, Equatable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public init(_ range: NSRange) {
        self.location = range.location
        self.length = range.length
    }

    public var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

public enum ConverterCandidateWindow: Codable, Sendable, Equatable {
    case hidden
    case composing([ConverterCandidatePresentation], selectionIndex: Int?)
    case selecting([ConverterCandidatePresentation], selectionIndex: Int?)
}

public struct ConverterPredictionCandidate: Codable, Sendable, Equatable {
    public var displayText: String
    public var appendText: String
    public var deleteCount: Int

    public init(_ prediction: SegmentsManager.PredictionCandidate) {
        self.displayText = prediction.displayText
        self.appendText = prediction.appendText
        self.deleteCount = prediction.deleteCount
    }

    public init(displayText: String, appendText: String, deleteCount: Int = 0) {
        self.displayText = displayText
        self.appendText = appendText
        self.deleteCount = deleteCount
    }
}

public struct ConverterCandidatePresentation: Codable, Sendable, Equatable {
    public var text: String
    public var annotationText: String?
    public var extraValues: [String: String]

    public init(_ presentation: CandidatePresentation) {
        self.text = presentation.candidate.text
        self.annotationText = presentation.displayContext.annotationText
        self.extraValues = presentation.displayContext.extraValues
    }

    public var candidatePresentation: CandidatePresentation {
        CandidatePresentation(
            candidate: Candidate(
                text: text,
                value: 0,
                composingCount: .surfaceCount(text.count),
                lastMid: 0,
                data: []
            ),
            displayContext: CandidatePresentationContext(
                annotationText: annotationText,
                extraValues: extraValues
            )
        )
    }
}
