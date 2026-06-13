import Foundation
import KanaKanjiConverterModule

/// Converter Process との通信で使う JSON codec。
///
/// XPC 自体には `Data` だけを流し、この型で `ConverterServerCommand` と
/// `ConverterServerResponse` へ変換する。これにより XPC の Objective-C
/// インターフェースと、Swift 側の Codable な通信契約を分離している。
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

/// Converter Process に送るトップレベルの命令。
///
/// セッションに属する処理は `session(sessionID:command:)` に集約し、
/// プロセス全体に作用する処理だけをこの enum に直接置く。
public enum ConverterServerCommand: Codable, Sendable {
    /// 応答を返したあとで Converter Process を終了する。
    ///
    /// LaunchAgent が KeepAlive 付きで登録されている場合は、終了後に launchd が
    /// 新しい Converter Process を起動する。
    case shutdown

    /// 指定したセッションへ命令を配送する。
    case session(sessionID: String, command: ConverterSessionCommand)
}

/// 1つの変換セッションに対する命令。
///
/// Client は IMK と UI に必要な副作用だけを担当し、変換状態、候補選択、設定値、
/// AI 置換候補などの状態は Server が保持する。この enum はそれらの責務ごとに
/// 命令をまとめており、通信仕様上の入口を読みやすく保つために平坦な case 群にはしていない。
public enum ConverterSessionCommand: Codable, Sendable {
    /// セッションの開始・停止に関する命令。
    case lifecycle(ConverterSessionLifecycleCommand)

    /// Server が列挙する設定項目と、その値の更新に関する命令。
    case settings(ConverterSettingsCommand)

    /// API key など、Client が実行時に渡すセッション設定を更新する。
    case updateConfig(ConverterSessionConfig)

    /// 1つのキーイベントを処理し、状態 snapshot と Client 側で実行する副作用を返す。
    case handleKeyEvent(ConverterKeyEventRequest)

    /// marked text の変換状態を操作・取得する命令。
    case composition(ConverterCompositionCommand)

    /// 通常の変換候補ウィンドウに対する選択・確定命令。
    case candidate(ConverterCandidateCommand)

    /// AI 置換候補の生成・選択・確定命令。
    case replaceSuggestion(ConverterReplaceSuggestionCommand)
}

/// 変換セッションのライフサイクル操作。
public enum ConverterSessionLifecycleCommand: Codable, Sendable {
    /// セッションが持つ `SegmentsManager` を有効化する。
    case activate

    /// セッションが持つ `SegmentsManager` を無効化する。
    case deactivate
}

/// Converter Process が公開する汎用設定の操作。
///
/// UI の実体は Client が描画するが、どの設定を表示するかという要求は Server が返す。
/// Client が未対応の種類は `requiresClientUpdate` 付きの descriptor として扱う。
public enum ConverterSettingsCommand: Codable, Sendable {
    /// Server が表示したい設定項目を列挙する。
    case list(capabilities: ConverterSettingClientCapabilities)

    /// 指定した設定キーの値を更新する。
    case update(key: String, value: ConverterSettingValue)
}

/// marked text と変換メモリに関する操作。
public enum ConverterCompositionCommand: Codable, Sendable {
    /// Client が持つ入力状態をもとに、現在の Server 状態 snapshot を返す。
    case snapshot(inputState: ConverterInputState)

    /// テキストを挿入せず、現在の composition を終了する。
    case stopComposition

    /// 現在選択中の学習候補を忘却する。
    case forgetMemory

    /// 現在の marked text を確定し、必要なら `insertText` effect を返す。
    case commit(inputState: ConverterInputState)
}

/// 通常の変換候補ウィンドウに対する操作。
public enum ConverterCandidateCommand: Codable, Sendable {
    /// 現在の候補ウィンドウで指定行を選択する。
    case selectCandidate(index: Int)

    /// 選択中の変換候補を確定する。
    case submitSelectedCandidate(context: ConverterTextContext)
}

/// AI 置換候補に対する操作。
public enum ConverterReplaceSuggestionCommand: Codable, Sendable {
    /// 現在の composition に対する置換候補を生成する。
    case request(context: ConverterTextContext)

    /// 置換候補ウィンドウで指定行を選択する。
    case selectReplaceSuggestionCandidate(index: Int)

    /// 選択中の置換候補を確定する。
    case submitSelectedReplaceSuggestion
}

/// Client が描画・実行できる汎用設定 UI の能力。
///
/// Server はこの情報を見て、Client がそのまま表示できる設定と、Client 更新が必要な設定を
/// 区別して descriptor を返す。
public struct ConverterSettingClientCapabilities: Codable, Sendable, Equatable {
    public var supportedKinds: Set<ConverterSettingKindIdentifier>
    public var supportedActions: Set<String>
    public var supportedCustomSurfaces: Set<String>

    public init(
        supportedKinds: Set<ConverterSettingKindIdentifier> = [],
        supportedActions: Set<String> = [],
        supportedCustomSurfaces: Set<String> = []
    ) {
        self.supportedKinds = supportedKinds
        self.supportedActions = supportedActions
        self.supportedCustomSurfaces = supportedCustomSurfaces
    }
}

/// 設定 UI の種類を表す安定した識別子。
public enum ConverterSettingKindIdentifier: String, Codable, Sendable, Hashable {
    case toggle
    case selector
    case textField
    case number
    case button
    case custom
}

/// Server が要求する設定 UI の形。
///
/// `toggle`、`selector`、`textField`、`number` は汎用描画できることを想定している。
/// `button` と `custom` は Client 側の明示的な対応が必要な操作・画面を表す。
public enum ConverterSettingKind: Codable, Sendable, Equatable {
    case toggle
    case selector(options: [ConverterSettingOption])
    case textField(secure: Bool)
    case number(min: Double?, max: Double?, step: Double?)
    case button(action: String)
    case custom(surface: String)

    public var identifier: ConverterSettingKindIdentifier {
        switch self {
        case .toggle:
            .toggle
        case .selector:
            .selector
        case .textField:
            .textField
        case .number:
            .number
        case .button:
            .button
        case .custom:
            .custom
        }
    }
}

/// 汎用設定で扱う値。
///
/// 設定の永続化自体は既存の `Config` 型が担い、この型は XPC で値を運ぶための
/// cross-platform な表現として使う。
public enum ConverterSettingValue: Codable, Sendable, Equatable {
    case bool(Bool)
    case string(String)
    case int(Int)
    case double(Double)
}

/// selector 設定に表示する1つの選択肢。
public struct ConverterSettingOption: Codable, Sendable, Equatable {
    public var title: String
    public var value: ConverterSettingValue

    public init(title: String, value: ConverterSettingValue) {
        self.title = title
        self.value = value
    }
}

/// Server が Client に表示を要求する1つの設定項目。
///
/// `requiresClientUpdate` が true の項目は、現在の Client では描画または操作できない。
/// その場合でも descriptor を返すことで、新しい Server がどの設定を追加したいのかを
/// Client 側で認識できる。
public struct ConverterSettingDescriptor: Codable, Sendable, Equatable {
    public var key: String
    public var title: String
    public var section: String
    public var kind: ConverterSettingKind
    public var value: ConverterSettingValue?
    public var isEnabled: Bool
    public var requiresClientUpdate: Bool

    public init(
        key: String,
        title: String,
        section: String,
        kind: ConverterSettingKind,
        value: ConverterSettingValue? = nil,
        isEnabled: Bool = true,
        requiresClientUpdate: Bool = false
    ) {
        self.key = key
        self.title = title
        self.section = section
        self.kind = kind
        self.value = value
        self.isEnabled = isEnabled
        self.requiresClientUpdate = requiresClientUpdate
    }
}

/// Client から Server へ渡すセッション単位の実行時設定。
///
/// Keychain や UI 状態など Client 側に残る情報を、必要な範囲だけ Server セッションへ同期する。
/// 永続設定の一覧・更新は `ConverterSettingsCommand` が担当する。
public struct ConverterSessionConfig: Codable, Sendable {
    public var aiBackendPreference: Config.AIBackendPreference.Value
    public var openAIModelName: String
    public var openAIEndpoint: String
    public var openAIAPIKey: ConverterSecretString
    public var includeContextInAITransform: Bool

    public init(
        aiBackendPreference: Config.AIBackendPreference.Value,
        openAIModelName: String,
        openAIEndpoint: String,
        openAIAPIKey: ConverterSecretString,
        includeContextInAITransform: Bool
    ) {
        self.aiBackendPreference = aiBackendPreference
        self.openAIModelName = openAIModelName
        self.openAIEndpoint = openAIEndpoint
        self.openAIAPIKey = openAIAPIKey
        self.includeContextInAITransform = includeContextInAITransform
    }
}

/// ログ出力時に値を伏せるための秘密文字列表現。
///
/// Codable では実値を運ぶが、`description` と `debugDescription` は `<redacted>` を返す。
public struct ConverterSecretString: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var value: String

    public init(_ value: String) {
        self.value = value
    }

    public var description: String {
        value.isEmpty ? "" : "<redacted>"
    }

    public var debugDescription: String {
        description
    }
}

/// 変換位置の前後にあるドキュメント文脈。
///
/// Client は macOS の text input API から取得できた範囲をこの型に詰めて Server に渡す。
/// どの処理で何文字使うかは Server 側が決めるため、各 command には maxCount を持たせない。
public struct ConverterTextContext: Codable, Sendable, Equatable {
    /// XPC で運ぶ文脈の上限。
    ///
    /// 実際に変換で使う長さは Server 側で用途別に切り詰める。
    public static let transportCharacterLimit = 200

    public var leftSideContext: String?
    public var rightSideContext: String?

    public init(leftSideContext: String? = nil, rightSideContext: String? = nil) {
        self.leftSideContext = leftSideContext
        self.rightSideContext = rightSideContext
    }
}

/// Client が受け取ったキーイベントと、その時点での IMK/UI 状態。
///
/// Server はこの情報だけを見て変換処理を進め、Client に必要な effect と snapshot を返す。
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
    public var enableOptionDirectFullWidthInput: Bool
    public var typeBackSlash: Bool
    public var optionDirectInputText: String?
    public var context: ConverterTextContext
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
        enableOptionDirectFullWidthInput: Bool = false,
        typeBackSlash: Bool = false,
        optionDirectInputText: String? = nil,
        context: ConverterTextContext = .init(),
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
        self.enableOptionDirectFullWidthInput = enableOptionDirectFullWidthInput
        self.typeBackSlash = typeBackSlash
        self.optionDirectInputText = optionDirectInputText
        self.context = context
        self.visibleCandidateStartIndex = visibleCandidateStartIndex
    }
}

/// Server が Client に実行を依頼する副作用。
///
/// `setMarkedText` や候補ウィンドウの描画は snapshot から Client が行う。
/// この enum は、アプリへの文字挿入、入力モード切替、Client 固有 UI の表示など、
/// Server プロセス内では完結できない操作だけを表す。
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

/// Converter Process から Client へ返す共通レスポンス。
///
/// 通常のキー処理、候補操作、設定取得などの応答をこの型にまとめる。
/// Client は `effects` を順に実行したあと、`snapshot` をもとに marked text と
/// 候補ウィンドウを更新する。
public struct ConverterServerResponse: Codable, Sendable {
    public var handled: Bool
    public var effects: [ConverterClientEffect]
    public var inputState: ConverterInputState
    public var inputLanguage: InputLanguage?
    public var settings: [ConverterSettingDescriptor]
    public var snapshot: ConverterSessionSnapshot

    public init(
        handled: Bool = true,
        effects: [ConverterClientEffect] = [],
        inputState: ConverterInputState = .none,
        inputLanguage: InputLanguage? = nil,
        settings: [ConverterSettingDescriptor] = [],
        snapshot: ConverterSessionSnapshot
    ) {
        self.handled = handled
        self.effects = effects
        self.inputState = inputState
        self.inputLanguage = inputLanguage
        self.settings = settings
        self.snapshot = snapshot
    }
}

/// Client が UI 反映に使う Server セッションの現在状態。
///
/// marked text、候補ウィンドウ、予測候補、AI 置換候補をまとめた読み取り専用の状態表現。
/// Client はこの snapshot を描画へ反映するだけで、変換状態の本体は Server 側に残す。
public struct ConverterSessionSnapshot: Codable, Sendable {
    public var markedText: ConverterMarkedText
    public var candidateWindow: ConverterCandidateWindow
    public var predictionCandidates: [ConverterPredictionCandidate]
    public var replaceSuggestionCandidates: [ConverterCandidatePresentation]
    public var replaceSuggestionSelectionIndex: Int?
    public var isEmpty: Bool
    public var convertTarget: String

    public init(
        markedText: ConverterMarkedText,
        candidateWindow: ConverterCandidateWindow,
        predictionCandidates: [ConverterPredictionCandidate] = [],
        replaceSuggestionCandidates: [ConverterCandidatePresentation] = [],
        replaceSuggestionSelectionIndex: Int? = nil,
        isEmpty: Bool,
        convertTarget: String
    ) {
        self.markedText = markedText
        self.candidateWindow = candidateWindow
        self.predictionCandidates = predictionCandidates
        self.replaceSuggestionCandidates = replaceSuggestionCandidates
        self.replaceSuggestionSelectionIndex = replaceSuggestionSelectionIndex
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

/// `InputState` を XPC で運ぶための Codable 表現。
///
/// macOS Client の内部型に依存しすぎないよう、通信境界ではこの型に変換する。
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

/// `InputStyle` を XPC で運ぶための Codable 表現。
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

/// marked text の描画に必要なテキスト断片と選択範囲。
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

/// `NSRange` を Codable にするための軽量表現。
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

/// 候補ウィンドウの表示状態。
public enum ConverterCandidateWindow: Codable, Sendable, Equatable {
    case hidden
    case composing([ConverterCandidatePresentation], selectionIndex: Int?)
    case selecting([ConverterCandidatePresentation], selectionIndex: Int?)
}

/// 予測入力候補として Client に表示する候補。
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

/// 通常候補・AI 置換候補を Client に表示するための候補情報。
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
