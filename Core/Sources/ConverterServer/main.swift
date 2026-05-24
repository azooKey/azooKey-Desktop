import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

private enum ConverterServerXPC {
    static let machServiceName = "dev.ensan.inputmethod.azooKeyMac.ConverterServer"
}

private enum ConverterCandidateTransform {
    case hiragana
    case katakana
    case halfWidthKatakana
    case fullWidthRoman
    case halfWidthRoman
}

@objc private protocol ConverterServerXPCProtocol {
    func openSession(with reply: @escaping @Sendable (String) -> Void)
    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void)
    func handleCommand(_ data: Data, with reply: @escaping @Sendable (Data?, NSString?) -> Void)
    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void)
}

private final class ConverterSession: SegmentManagerDelegate {
    let manager: SegmentsManager
    private var leftSideContext: String?

    init(manager: SegmentsManager) {
        self.manager = manager
        self.manager.delegate = self
    }

    func setLeftSideContext(_ value: String?) {
        self.leftSideContext = value
    }

    func getLeftSideContext(maxCount: Int) -> String? {
        guard let leftSideContext else {
            return nil
        }
        return String(leftSideContext.suffix(maxCount))
    }
}

private final class ConverterServer: NSObject, ConverterServerXPCProtocol, @unchecked Sendable {
    private var sessions: [String: ConverterSession] = [:]

    func openSession(with reply: @escaping @Sendable (String) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let sessionID = UUID().uuidString
                self.sessions[sessionID] = ConverterSession(manager: Self.makeSegmentsManager())
                reply(sessionID)
            }
        }
    }

    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let removed = self.sessions.removeValue(forKey: sessionID) != nil
                reply(removed)
            }
        }
    }

    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void) {
        reply("ConverterServer: \(message)")
    }

    func handleCommand(_ data: Data, with reply: @escaping @Sendable (Data?, NSString?) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                do {
                    let command = try ConverterServerCodec.decodeCommand(from: data)
                    let response = try self.handle(command)
                    reply(try ConverterServerCodec.encode(response), nil)
                } catch {
                    reply(nil, error.localizedDescription as NSString)
                }
            }
        }
    }

    @MainActor
    private func handle(_ command: ConverterServerCommand) throws -> ConverterServerResponse {
        switch command {
        case .activate(let sessionID):
            let session = try getSession(sessionID)
            session.manager.activate()
            return makeResponse(for: session, inputState: .none)
        case .deactivate(let sessionID):
            let session = try getSession(sessionID)
            session.manager.deactivate()
            return makeResponse(for: session, inputState: .none)
        case .snapshot(let sessionID, let inputState):
            return makeResponse(for: try getSession(sessionID), inputState: inputState.inputState)
        case .stopComposition(let sessionID):
            let session = try getSession(sessionID)
            session.manager.stopComposition()
            return makeResponse(for: session, inputState: .none)
        case .forgetMemory(let sessionID):
            let session = try getSession(sessionID)
            session.manager.forgetMemory()
            return makeResponse(for: session, inputState: .none)
        case .handleKeyEvent(let sessionID, let request):
            return try handleKeyEvent(sessionID: sessionID, request: request)
        case .selectCandidate(let sessionID, let index):
            let session = try getSession(sessionID)
            session.manager.requestSelectingRow(index)
            return makeResponse(for: session, inputState: .selecting)
        case .submitSelectedCandidate(let sessionID, let leftSideContext):
            let session = try getSession(sessionID)
            var effects: [ConverterClientEffect] = []
            submitSelectedCandidate(manager: session.manager, leftSideContext: leftSideContext, effects: &effects)
            let nextInputState: InputState = session.manager.isEmpty ? .none : .previewing
            return makeResponse(
                for: session,
                inputState: nextInputState,
                effects: effects,
                responseInputState: ConverterInputState(nextInputState)
            )
        case .commitComposition(let sessionID, let inputState):
            let session = try getSession(sessionID)
            let text = session.manager.commitMarkedText(inputState: inputState.inputState)
            let effects: [ConverterClientEffect] = text.isEmpty ? [] : [.insertText(text)]
            return makeResponse(for: session, inputState: .none, effects: effects, responseInputState: ConverterInputState.none)
        }
    }

    @MainActor
    private func handleKeyEvent(
        sessionID: String,
        request: ConverterKeyEventRequest
    ) throws -> ConverterServerResponse {
        guard let session = sessions[sessionID] else {
            throw ConverterServerError.unknownSession(sessionID)
        }
        session.setLeftSideContext(request.leftSideContext)
        Config.DebugPredictiveTyping().value = request.enablePredictiveTyping
        Config.DebugTypoCorrection().value = request.enableTypoCorrection

        let userAction = UserAction.getUserAction(
            eventCore: request.event,
            inputLanguage: request.inputLanguage
        )
        let (clientAction, clientActionCallback) = request.inputState.inputState.event(
            eventCore: request.event,
            userAction: userAction,
            inputLanguage: request.inputLanguage,
            liveConversionEnabled: request.liveConversionEnabled,
            enableDebugWindow: request.enableDebugWindow,
            enableSuggestion: request.enableSuggestion
        )

        var effects: [ConverterClientEffect] = []
        var inputLanguage = request.inputLanguage
        let actionHandled = perform(
            clientAction,
            request: request,
            session: session,
            inputLanguage: &inputLanguage,
            effects: &effects
        )
        guard actionHandled else {
            return ConverterServerResponse(
                handled: false,
                effects: effects,
                inputState: request.inputState,
                inputLanguage: inputLanguage,
                snapshot: snapshot(for: session.manager, inputState: request.inputState.inputState)
            )
        }

        let nextInputState = apply(
            clientActionCallback,
            currentInputState: request.inputState.inputState,
            compositionIsEmpty: session.manager.isEmpty
        )
        return ConverterServerResponse(
            handled: !effects.contains(.fallthroughToApplication),
            effects: effects,
            inputState: ConverterInputState(nextInputState),
            inputLanguage: inputLanguage,
            snapshot: snapshot(for: session.manager, inputState: nextInputState)
        )
    }

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func perform(
        _ action: ClientAction,
        request: ConverterKeyEventRequest,
        session: ConverterSession,
        inputLanguage: inout InputLanguage,
        effects: inout [ConverterClientEffect]
    ) -> Bool {
        let manager = session.manager
        let inputState = request.inputState.inputState
        let inputStyle = Self.resolveInputStyle(request.inputLanguage == .english ? .direct : request.inputStyle)
        switch action {
        case .consume:
            return true
        case .fallthrough:
            effects.append(.fallthroughToApplication)
            return true
        case .showCandidateWindow:
            manager.requestSetCandidateWindowState(visible: true)
        case .hideCandidateWindow:
            manager.requestSetCandidateWindowState(visible: false)
        case .appendToMarkedText(let text):
            manager.insertAtCursorPosition(text, inputStyle: inputStyle)
        case .appendPieceToMarkedText(let pieces):
            manager.insertAtCursorPosition(pieces: pieces, inputStyle: inputStyle)
        case .insertWithoutMarkedText(let text):
            effects.append(.insertText(text))
        case .removeLastMarkedText:
            manager.deleteBackwardFromCursorPosition()
            manager.requestResettingSelection()
        case .commitMarkedText:
            let text = manager.commitMarkedText(inputState: inputState)
            if !text.isEmpty {
                effects.append(.insertText(text))
            }
        case .editSegment(let count):
            manager.editSegment(count: count)
        case .enterFirstCandidatePreviewMode:
            manager.insertCompositionSeparator(inputStyle: inputStyle, skipUpdate: false)
            manager.requestSetCandidateWindowState(visible: false)
        case .enterCandidateSelectionMode:
            manager.insertCompositionSeparator(inputStyle: inputStyle, skipUpdate: true)
            manager.update(requestRichCandidates: true)
        case .submitSelectedCandidate:
            submitSelectedCandidate(manager: manager, leftSideContext: request.leftSideContext, effects: &effects)
        case .selectNextCandidate:
            manager.requestSelectingNextCandidate()
        case .selectPrevCandidate:
            manager.requestSelectingPrevCandidate()
        case .selectNumberCandidate(let number):
            manager.requestSelectingRow(request.visibleCandidateStartIndex + number - 1)
            submitSelectedCandidate(manager: manager, leftSideContext: request.leftSideContext, effects: &effects)
            manager.requestResettingSelection()
        case .selectInputLanguage(let language):
            manager.stopComposition()
            inputLanguage = language
            effects.append(.switchInputLanguage(language))
        case .commitMarkedTextAndSelectInputLanguage(let language):
            let text = manager.commitMarkedText(inputState: inputState)
            if !text.isEmpty {
                effects.append(.insertText(text))
            }
            inputLanguage = language
            effects.append(.switchInputLanguage(language))
        case .commitMarkedTextAndAppendToMarkedText(let text):
            commitMarkedTextAndContinue(
                manager: manager,
                inputState: inputState,
                effects: &effects
            )
            manager.insertAtCursorPosition(text, inputStyle: inputStyle)
        case .commitMarkedTextAndAppendPieceToMarkedText(let pieces):
            commitMarkedTextAndContinue(
                manager: manager,
                inputState: inputState,
                effects: &effects
            )
            manager.insertAtCursorPosition(pieces: pieces, inputStyle: inputStyle)
        case .enableDebugWindow:
            manager.requestDebugWindowMode(enabled: true)
        case .disableDebugWindow:
            manager.requestDebugWindowMode(enabled: false)
        case .forgetMemory:
            manager.forgetMemory()
        case .submitKatakanaCandidate:
            submitTransformedCandidate(.katakana, manager: manager, inputState: inputState, leftSideContext: request.leftSideContext, effects: &effects)
        case .submitHiraganaCandidate:
            submitTransformedCandidate(.hiragana, manager: manager, inputState: inputState, leftSideContext: request.leftSideContext, effects: &effects)
        case .submitHankakuKatakanaCandidate:
            submitTransformedCandidate(.halfWidthKatakana, manager: manager, inputState: inputState, leftSideContext: request.leftSideContext, effects: &effects)
        case .submitFullWidthRomanCandidate:
            submitTransformedCandidate(.fullWidthRoman, manager: manager, inputState: inputState, leftSideContext: request.leftSideContext, effects: &effects)
        case .submitHalfWidthRomanCandidate:
            submitTransformedCandidate(.halfWidthRoman, manager: manager, inputState: inputState, leftSideContext: request.leftSideContext, effects: &effects)
        case .requestPredictiveSuggestion:
            manager.insertAtCursorPosition("つづき", inputStyle: inputStyle)
            effects.append(.requestReplaceSuggestion)
        case .acceptPredictionCandidate:
            acceptPredictionCandidate(manager: manager, leftSideContext: request.leftSideContext)
        case .requestReplaceSuggestion:
            effects.append(.requestReplaceSuggestion)
        case .selectNextReplaceSuggestionCandidate:
            effects.append(.selectNextReplaceSuggestionCandidate)
        case .selectPrevReplaceSuggestionCandidate:
            effects.append(.selectPreviousReplaceSuggestionCandidate)
        case .submitReplaceSuggestionCandidate:
            effects.append(.submitReplaceSuggestionCandidate)
        case .hideReplaceSuggestionWindow:
            effects.append(.hideReplaceSuggestionWindow)
        case .showPromptInputWindow:
            effects.append(.showPromptInputWindow)
        case .transformSelectedText(let selectedText, let prompt):
            effects.append(.transformSelectedText(selectedText, prompt))
        case .enterUnicodeInputMode, .appendToUnicodeInput, .removeLastUnicodeInput, .cancelUnicodeInput:
            return true
        case .submitUnicodeInput(let codePoint):
            if let scalar = UInt32(codePoint, radix: 16), let unicodeScalar = Unicode.Scalar(scalar) {
                effects.append(.insertText(String(Character(unicodeScalar))))
            }
        case .submitSelectedCandidateAndEnterUnicodeInputMode:
            submitSelectedCandidate(manager: manager, leftSideContext: request.leftSideContext, effects: &effects)
            if !manager.isEmpty {
                effects.append(.insertText(manager.convertTarget))
                manager.stopComposition()
            }
        case .stopComposition:
            manager.stopComposition()
        }
        return true
    }

    @MainActor
    private func apply(
        _ callback: ClientActionCallback,
        currentInputState: InputState,
        compositionIsEmpty: Bool
    ) -> InputState {
        switch callback {
        case .fallthrough:
            return currentInputState
        case .transition(let inputState):
            return inputState
        case .basedOnBackspace(let ifIsEmpty, let ifIsNotEmpty),
             .basedOnSubmitCandidate(let ifIsEmpty, let ifIsNotEmpty):
            return compositionIsEmpty ? ifIsEmpty : ifIsNotEmpty
        }
    }

    @MainActor
    private func commitMarkedTextAndContinue(
        manager: SegmentsManager,
        inputState: InputState,
        effects: inout [ConverterClientEffect]
    ) {
        let text = manager.commitMarkedText(inputState: inputState)
        if !text.isEmpty {
            effects.append(.insertText(text))
        }
    }

    @MainActor
    private func submitSelectedCandidate(
        manager: SegmentsManager,
        leftSideContext: String?,
        effects: inout [ConverterClientEffect]
    ) {
        guard let candidate = manager.selectedCandidate else {
            return
        }
        manager.prefixCandidateCommited(candidate, leftSideContext: leftSideContext ?? "")
        effects.append(.insertText(candidate.text))
    }

    @MainActor
    private func submitTransformedCandidate(
        _ transform: ConverterCandidateTransform,
        manager: SegmentsManager,
        inputState: InputState,
        leftSideContext: String?,
        effects: inout [ConverterClientEffect]
    ) {
        let candidate = Self.transformedCandidate(transform, manager: manager, inputState: inputState)
        manager.prefixCandidateCommited(candidate, leftSideContext: leftSideContext ?? "")
        effects.append(.insertText(candidate.text))
    }

    @MainActor
    private func acceptPredictionCandidate(manager: SegmentsManager, leftSideContext _: String?) {
        let prediction = SegmentsManager.preferredPredictionCandidates(
            typoCorrectionCandidates: manager.requestTypoCorrectionPredictionCandidates(),
            predictionCandidates: manager.requestPredictionCandidates()
        ).first
        guard let prediction else {
            return
        }
        if prediction.deleteCount > 0 {
            manager.deleteBackwardFromCursorPosition(count: prediction.deleteCount)
        }
        guard !prediction.appendText.isEmpty else {
            return
        }
        manager.insertAtCursorPosition(prediction.appendText, inputStyle: .direct)
    }

    @MainActor
    private func getSession(_ sessionID: String) throws -> ConverterSession {
        guard let session = sessions[sessionID] else {
            throw ConverterServerError.unknownSession(sessionID)
        }
        return session
    }

    @MainActor
    private func makeResponse(
        for session: ConverterSession,
        inputState: InputState,
        handled: Bool = true,
        effects: [ConverterClientEffect] = [],
        responseInputState: ConverterInputState? = nil
    ) -> ConverterServerResponse {
        ConverterServerResponse(
            handled: handled,
            effects: effects,
            inputState: responseInputState ?? ConverterInputState(inputState),
            snapshot: snapshot(for: session.manager, inputState: inputState)
        )
    }

    @MainActor
    private func snapshot(for manager: SegmentsManager, inputState: InputState) -> ConverterSessionSnapshot {
        if manager.isEmpty {
            return .empty
        }
        let markedText = ConverterMarkedText(manager.getCurrentMarkedText(inputState: inputState))
        let candidateWindow: ConverterCandidateWindow
        switch manager.getCurrentCandidateWindow(inputState: inputState) {
        case .hidden:
            candidateWindow = .hidden
        case .composing(let candidates, let selectionIndex):
            candidateWindow = .composing(
                manager.makeCandidatePresentations(candidates).map(ConverterCandidatePresentation.init),
                selectionIndex: selectionIndex
            )
        case .selecting(let candidates, let selectionIndex):
            candidateWindow = .selecting(
                manager.makeCandidatePresentations(candidates).map(ConverterCandidatePresentation.init),
                selectionIndex: selectionIndex
            )
        }
        let predictionCandidates: [ConverterPredictionCandidate]
        if inputState == .composing {
            predictionCandidates = SegmentsManager.preferredPredictionCandidates(
                typoCorrectionCandidates: manager.requestTypoCorrectionPredictionCandidates(),
                predictionCandidates: manager.requestPredictionCandidates()
            ).map(ConverterPredictionCandidate.init)
        } else {
            predictionCandidates = []
        }
        return ConverterSessionSnapshot(
            markedText: markedText,
            candidateWindow: candidateWindow,
            predictionCandidates: predictionCandidates,
            isEmpty: manager.isEmpty,
            convertTarget: manager.convertTarget
        )
    }

    @MainActor
    private static func makeSegmentsManager() -> SegmentsManager {
        CustomInputTableStore.registerIfExists()
        let containerURL = AppGroup.containerURL()
        return SegmentsManager(
            kanaKanjiConverter: KanaKanjiConverter.withDefaultDictionary(),
            applicationDirectoryURL: AppGroup.memoryDirectoryURL(),
            containerURL: containerURL,
            context: .init(useZenzai: true, resourcesDirectoryURL: appResourcesDirectoryURL())
        )
    }

    private static func appResourcesDirectoryURL() -> URL {
        if let executableURL = Bundle.main.executableURL {
            return executableURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources", isDirectory: true)
        }
        if let resourceURL = Bundle.main.resourceURL {
            return resourceURL
        }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
    }

    @MainActor
    private static func resolveInputStyle(_ inputStyle: ConverterInputStyle) -> InputStyle {
        if case .tableName(CustomInputTableStore.tableName) = inputStyle,
           !CustomInputTableStore.registerIfExists() {
            return .mapped(id: .defaultRomanToKana)
        }
        return inputStyle.inputStyle
    }

    @MainActor
    private static func transformedCandidate(
        _ transform: ConverterCandidateTransform,
        manager: SegmentsManager,
        inputState: InputState
    ) -> Candidate {
        switch transform {
        case .hiragana:
            manager.getModifiedRubyCandidate(inputState: inputState) {
                $0.toHiragana()
            }
        case .katakana:
            manager.getModifiedRubyCandidate(inputState: inputState) {
                $0.toKatakana()
            }
        case .halfWidthKatakana:
            manager.getModifiedRubyCandidate(inputState: inputState) {
                $0.toKatakana().applyingTransform(.fullwidthToHalfwidth, reverse: false)!
            }
        case .fullWidthRoman:
            manager.getModifiedRomanCandidate(inputState: inputState) {
                $0.applyingTransform(.fullwidthToHalfwidth, reverse: true)!
            }
        case .halfWidthRoman:
            manager.getModifiedRomanCandidate(inputState: inputState) {
                $0.applyingTransform(.fullwidthToHalfwidth, reverse: false)!
            }
        }
    }
}

private enum ConverterServerError: LocalizedError {
    case unknownSession(String)

    var errorDescription: String? {
        switch self {
        case .unknownSession(let sessionID):
            "Unknown converter session: \(sessionID)"
        }
    }
}

private final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let server = ConverterServer()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ConverterServerXPCProtocol.self)
        connection.exportedObject = server
        connection.resume()
        return true
    }
}

let listener = NSXPCListener(machServiceName: ConverterServerXPC.machServiceName)
private let delegate = ServiceDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
