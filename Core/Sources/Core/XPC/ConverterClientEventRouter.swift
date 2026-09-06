import Foundation

/// InputMethodKit の同期 `handle` が返すイベント所有権だけを判断する。
///
/// 変換状態の本体は ConverterServer が所有する。Client は Server が最後に返した
/// 読み取り専用の状態を使い、明らかな application shortcut を同期的に通す。
/// キーごとに Server の応答を同期的に反映するため、未応答のキーを推測する必要はない。
public enum ConverterClientEventDisposition: Sendable, Equatable {
    case sendToServer
    case fallthroughToApplication
    case insertText(String)
}

public struct ConverterClientEventRoutingContext: Sendable, Equatable {
    public var acknowledgedInputState: ConverterInputState
    public var acknowledgedInputLanguage: InputLanguage
    public var liveConversionEnabled: Bool
    public var enableDebugWindow: Bool
    public var enableSuggestion: Bool
    public var typeBackSlash: Bool

    public init(
        acknowledgedInputState: ConverterInputState = .none,
        acknowledgedInputLanguage: InputLanguage = .japanese,
        liveConversionEnabled: Bool = true,
        enableDebugWindow: Bool = false,
        enableSuggestion: Bool = false,
        typeBackSlash: Bool = false
    ) {
        self.acknowledgedInputState = acknowledgedInputState
        self.acknowledgedInputLanguage = acknowledgedInputLanguage
        self.liveConversionEnabled = liveConversionEnabled
        self.enableDebugWindow = enableDebugWindow
        self.enableSuggestion = enableSuggestion
        self.typeBackSlash = typeBackSlash
    }
}

public enum ConverterClientEventRouter {
    public static func disposition(
        event: KeyEventCore,
        context: ConverterClientEventRoutingContext
    ) -> ConverterClientEventDisposition {
        // Command shortcut は composition の有無にかかわらず application が所有する。
        if event.modifierFlags.contains(.command) {
            return .fallthroughToApplication
        }

        let inputState = context.acknowledgedInputState.inputState
        let userAction = UserAction.getUserAction(
            eventCore: event,
            inputLanguage: context.acknowledgedInputLanguage,
            typeBackSlash: context.typeBackSlash
        )
        let (action, _) = inputState.event(
            eventCore: event,
            userAction: userAction,
            inputLanguage: context.acknowledgedInputLanguage,
            liveConversionEnabled: context.liveConversionEnabled,
            enableDebugWindow: context.enableDebugWindow,
            enableSuggestion: context.enableSuggestion
        )
        if case .fallthrough = action {
            return .fallthroughToApplication
        }
        if context.acknowledgedInputLanguage == .english,
           context.acknowledgedInputState == .none,
           case .insertWithoutMarkedText(let text) = action {
            // 通常の直接入力は application に任せる。円記号・バックスラッシュ等、
            // azooKey の設定による置き換えが必要な場合だけ、その場で挿入する。
            return text == event.characters ? .fallthroughToApplication : .insertText(text)
        }
        return .sendToServer
    }
}
