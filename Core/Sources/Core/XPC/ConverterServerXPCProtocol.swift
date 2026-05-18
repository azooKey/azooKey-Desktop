import Foundation
import KanaKanjiConverterModule

public enum ConverterServerProtocol {
    public static let currentVersion = 1
    public static let minimumSupportedClientVersion = 1
}

public enum ConverterServerCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode(_ info: ConverterServerInfo) throws -> Data {
        try encoder.encode(info)
    }

    public static func decodeServerInfo(from data: Data) throws -> ConverterServerInfo {
        try decoder.decode(ConverterServerInfo.self, from: data)
    }

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

public struct ConverterServerInfo: Codable, Sendable, Equatable {
    public var protocolVersion: Int
    public var minimumClientProtocolVersion: Int
    public var supportedCommands: [String]
    public var serverKind: String
    public var buildIdentifier: String?

    public init(
        protocolVersion: Int,
        minimumClientProtocolVersion: Int,
        supportedCommands: [String],
        serverKind: String,
        buildIdentifier: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.minimumClientProtocolVersion = minimumClientProtocolVersion
        self.supportedCommands = supportedCommands
        self.serverKind = serverKind
        self.buildIdentifier = buildIdentifier
    }

    public func isCompatibleWithClient(protocolVersion clientProtocolVersion: Int) -> Bool {
        minimumClientProtocolVersion <= clientProtocolVersion
    }

    public func supports(_ commandName: ConverterServerCommandName) -> Bool {
        supportedCommands.contains(commandName.rawValue)
    }
}

public enum ConverterServerCommandName: String, Codable, Sendable, CaseIterable {
    case activate
    case deactivate
    case snapshot
    case stopComposition
    case insertText
    case insertCompositionSeparator
    case updateCandidates
    case deleteBackward
    case editSegment
    case setCandidateWindowVisible
    case selectNextCandidate
    case selectPreviousCandidate
    case selectCandidate
    case resetSelection
    case submitSelectedCandidate
    case submitTransformedCandidate
    case commitMarkedText
    case forgetMemory
}

public enum ConverterServerCommand: Codable, Sendable {
    case activate(sessionID: String)
    case deactivate(sessionID: String)
    case snapshot(sessionID: String, inputState: ConverterInputState)
    case stopComposition(sessionID: String)
    case insertText(sessionID: String, text: String, inputStyle: ConverterInputStyle, leftSideContext: String?)
    case insertCompositionSeparator(sessionID: String, inputStyle: ConverterInputStyle, skipUpdate: Bool)
    case updateCandidates(sessionID: String, requestRichCandidates: Bool)
    case deleteBackward(sessionID: String, count: Int, leftSideContext: String?)
    case editSegment(sessionID: String, count: Int)
    case setCandidateWindowVisible(sessionID: String, visible: Bool, inputState: ConverterInputState)
    case selectNextCandidate(sessionID: String)
    case selectPreviousCandidate(sessionID: String)
    case selectCandidate(sessionID: String, index: Int)
    case resetSelection(sessionID: String)
    case submitSelectedCandidate(sessionID: String, leftSideContext: String?)
    case submitTransformedCandidate(sessionID: String, transform: ConverterCandidateTransform, inputState: ConverterInputState, leftSideContext: String?)
    case commitMarkedText(sessionID: String, inputState: ConverterInputState)
    case forgetMemory(sessionID: String)

    public var commandName: ConverterServerCommandName {
        switch self {
        case .activate:
            .activate
        case .deactivate:
            .deactivate
        case .snapshot:
            .snapshot
        case .stopComposition:
            .stopComposition
        case .insertText:
            .insertText
        case .insertCompositionSeparator:
            .insertCompositionSeparator
        case .updateCandidates:
            .updateCandidates
        case .deleteBackward:
            .deleteBackward
        case .editSegment:
            .editSegment
        case .setCandidateWindowVisible:
            .setCandidateWindowVisible
        case .selectNextCandidate:
            .selectNextCandidate
        case .selectPreviousCandidate:
            .selectPreviousCandidate
        case .selectCandidate:
            .selectCandidate
        case .resetSelection:
            .resetSelection
        case .submitSelectedCandidate:
            .submitSelectedCandidate
        case .submitTransformedCandidate:
            .submitTransformedCandidate
        case .commitMarkedText:
            .commitMarkedText
        case .forgetMemory:
            .forgetMemory
        }
    }
}

public enum ConverterCandidateTransform: Codable, Sendable {
    case hiragana
    case katakana
    case halfWidthKatakana
    case fullWidthRoman
    case halfWidthRoman
}

public struct ConverterServerResponse: Codable, Sendable {
    public var sessionID: String
    public var committedText: String?
    public var snapshot: ConverterSessionSnapshot

    public init(sessionID: String, committedText: String? = nil, snapshot: ConverterSessionSnapshot) {
        self.sessionID = sessionID
        self.committedText = committedText
        self.snapshot = snapshot
    }
}

public struct ConverterSessionSnapshot: Codable, Sendable {
    public var markedText: ConverterMarkedText
    public var candidateWindow: ConverterCandidateWindow
    public var isEmpty: Bool
    public var convertTarget: String

    public init(
        markedText: ConverterMarkedText,
        candidateWindow: ConverterCandidateWindow,
        isEmpty: Bool,
        convertTarget: String
    ) {
        self.markedText = markedText
        self.candidateWindow = candidateWindow
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

    var inputStateFromCandidateWindow: InputState? {
        switch candidateWindow {
        case .selecting:
            .selecting
        case .composing:
            .composing
        case .hidden:
            nil
        }
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
