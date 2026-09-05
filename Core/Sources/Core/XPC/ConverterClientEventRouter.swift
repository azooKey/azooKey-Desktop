import Foundation

/// InputMethodKit の同期 `handle` が返すイベント所有権だけを判断する。
///
/// 変換状態の本体は ConverterServer が所有する。Client は Server が最後に返した
/// 読み取り専用の状態を使い、明らかな application shortcut を同期的に通す。
/// Server の応答待ちがある間は状態が進んでいる可能性があるため、Command shortcut
/// 以外を保守的に consume し、生のキー入力が application へ漏れることを防ぐ。
public enum ConverterClientEventDisposition: Sendable, Equatable {
    case sendToServer
    case fallthroughToApplication
}

public struct ConverterClientEventRoutingContext: Sendable, Equatable {
    public var acknowledgedInputState: ConverterInputState
    public var acknowledgedInputLanguage: InputLanguage
    public var hasPendingKeyEvents: Bool
    public var liveConversionEnabled: Bool
    public var enableDebugWindow: Bool
    public var enableSuggestion: Bool
    public var typeBackSlash: Bool

    public init(
        acknowledgedInputState: ConverterInputState = .none,
        acknowledgedInputLanguage: InputLanguage = .japanese,
        hasPendingKeyEvents: Bool = false,
        liveConversionEnabled: Bool = true,
        enableDebugWindow: Bool = false,
        enableSuggestion: Bool = false,
        typeBackSlash: Bool = false
    ) {
        self.acknowledgedInputState = acknowledgedInputState
        self.acknowledgedInputLanguage = acknowledgedInputLanguage
        self.hasPendingKeyEvents = hasPendingKeyEvents
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

        // 未応答イベントがある場合、acknowledgedInputState は古い可能性がある。
        // ここで fallthrough するとタイムアウトした文字が英字として漏れるため、
        // Server が順番に処理できるようイベントを consume する。
        if context.hasPendingKeyEvents {
            return .sendToServer
        }

        if case .fallthrough = Self.clientAction(event: event, context: context) {
            return .fallthroughToApplication
        }
        return .sendToServer
    }

    /// Server の応答を待つ間、application へ同期的に置く暫定の marked text
    /// 未確定文字列が無い状態の最初の文字が生のキーとして漏れるのを防ぐ。
    public static func provisionalMarkedText(
        event: KeyEventCore,
        context: ConverterClientEventRoutingContext
    ) -> String? {
        guard context.acknowledgedInputState == .none else {
            return nil
        }
        switch Self.clientAction(event: event, context: context) {
        case .appendPieceToMarkedText(let pieces):
            return pieces.inputString(preferIntention: false)
        case .insertWithoutMarkedText(let text):
            return text
        default:
            return nil
        }
    }

    private static func clientAction(
        event: KeyEventCore,
        context: ConverterClientEventRoutingContext
    ) -> ClientAction {
        let userAction = UserAction.getUserAction(
            eventCore: event,
            inputLanguage: context.acknowledgedInputLanguage,
            typeBackSlash: context.typeBackSlash
        )
        let (action, _) = context.acknowledgedInputState.inputState.event(
            eventCore: event,
            userAction: userAction,
            inputLanguage: context.acknowledgedInputLanguage,
            liveConversionEnabled: context.liveConversionEnabled,
            enableDebugWindow: context.enableDebugWindow,
            enableSuggestion: context.enableSuggestion
        )
        return action
    }
}
