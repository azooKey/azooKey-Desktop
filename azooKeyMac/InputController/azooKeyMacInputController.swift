import Cocoa
import Core
import InputMethodKit

@objc(azooKeyMacInputController)
class azooKeyMacInputController: IMKInputController, NSMenuItemValidation { // swiftlint:disable:this type_name
    let converterServerClient = ConverterServerClient()
    private var currentConverterView: ConverterSessionSnapshot?
    private(set) var inputState: InputState = .none
    private var inputLanguage: InputLanguage = .japanese
    private var pendingKeyEventCount = 0
    private var nextKeyEventID: UInt64 = 0
    private var activationGeneration: UInt64 = 0
    private var pendingConverterServerActivation: ConverterSessionActivation?
    var liveConversionEnabled: Bool {
        Config.LiveConversion().value
    }

    var appMenu: NSMenu
    var liveConversionToggleMenuItem: NSMenuItem
    var transformSelectedTextMenuItem: NSMenuItem

    private var candidatesWindow: NSWindow
    private var candidatesViewController: CandidatesViewController

    private var predictionWindow: NSWindow
    private var predictionViewController: PredictionCandidatesViewController
    private var lastPredictionCandidates: [String] = []
    private var lastPredictionUpdateTime: TimeInterval = 0
    private var predictionHideWorkItem: DispatchWorkItem?

    private var replaceSuggestionWindow: NSWindow
    private var replaceSuggestionsViewController: ReplaceSuggestionsViewController

    var promptInputWindow: PromptInputWindow
    var isPromptWindowVisible: Bool = false

    // ダブルタップ検出用
    private var lastKey: (time: TimeInterval, code: UInt16) = (0, 0)
    private static let doubleTapInterval: TimeInterval = 0.5
    private static let candidateWindowInitialSize = CGSize(width: 400, height: 1000)

    // ピン留めプロンプトのキャッシュ（パフォーマンス向上のため）
    private var pinnedPromptsCache: [PromptHistoryItem] = []

    func appendDebugMessage(_ message: String) {
        NSLog("azooKeyMac: %@", message)
    }

    private static func makeCandidateWindow(contentViewController: NSViewController) -> NSWindow {
        let window = NSWindow(contentViewController: contentViewController)
        window.styleMask = [.borderless]
        window.level = .popUpMenu

        // Chromium 系アプリの deadlock 回避のため、初期化時に client への
        // 問い合わせを行わない（Chromium issue 503787240）。
        // ウィンドウは直後に orderOut されるため origin はユーザーから不可視であり、
        // 最初の候補表示時に refreshCandidateWindow() で正しい位置に再配置される。
        var frame = NSRect.zero
        frame.size = candidateWindowInitialSize
        window.setFrame(frame, display: true)
        window.setIsVisible(false)
        window.orderOut(nil)
        return window
    }

    // MARK: - ダブルタップ検出
    private func checkAndUpdateDoubleTap(keyCode: UInt16) -> Bool {
        let now = Date().timeIntervalSince1970
        let isDouble = (self.lastKey.code == keyCode) && (now - self.lastKey.time < Self.doubleTapInterval)
        self.lastKey = (time: now, code: keyCode)
        return isDouble
    }

    /// ピン留めプロンプトのキャッシュを更新
    func reloadPinnedPromptsCache() {
        guard let data = Config.data(forKey: Config.PromptHistory.key),
              let history = try? JSONDecoder().decode([PromptHistoryItem].self, from: data) else {
            self.pinnedPromptsCache = []
            return
        }
        self.pinnedPromptsCache = history.filter { $0.isPinned }
    }

    // MARK: - カスタムプロンプトショートカット検出
    private func checkCustomPromptShortcut(event: NSEvent) -> String? {
        guard let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty else {
            return nil
        }

        let key = characters.lowercased()
        let eventModifiers = KeyEventCore.ModifierFlag(from: event.modifierFlags)

        // 修飾キーがない場合は早期リターン（通常の入力）
        if eventModifiers.isEmpty {
            return nil
        }

        // キャッシュからショートカット付きのピン留めプロンプトを検索
        if let matched = self.pinnedPromptsCache.first(where: { item in
            guard let itemShortcut = item.shortcut else {
                return false
            }
            return itemShortcut.key == key && itemShortcut.modifiers == eventModifiers
        }) {
            return matched.prompt
        }

        return nil
    }

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        self.appMenu = NSMenu(title: "azooKey")
        self.liveConversionToggleMenuItem = NSMenuItem()
        self.transformSelectedTextMenuItem = NSMenuItem()

        let candidatesViewController = CandidatesViewController()
        let predictionViewController = PredictionCandidatesViewController()
        let replaceSuggestionsViewController = ReplaceSuggestionsViewController()

        self.candidatesViewController = candidatesViewController
        self.predictionViewController = predictionViewController
        self.replaceSuggestionsViewController = replaceSuggestionsViewController

        self.candidatesWindow = Self.makeCandidateWindow(contentViewController: candidatesViewController)
        self.predictionWindow = Self.makeCandidateWindow(contentViewController: predictionViewController)
        self.replaceSuggestionWindow = Self.makeCandidateWindow(contentViewController: replaceSuggestionsViewController)

        // PromptInputWindowの初期化
        self.promptInputWindow = PromptInputWindow()

        super.init(server: server, delegate: delegate, client: inputClient)

        // デリゲートの設定を super.init の後に移動
        self.candidatesViewController.delegate = self
        self.replaceSuggestionsViewController.delegate = self
        MainActor.assumeIsolated {
            self.converterServerClient.onLog = { [weak self] message in
                self?.appendDebugMessage(message)
            }
        }
        self.setupMenu()
    }

    @MainActor
    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        self.activationGeneration &+= 1
        self.updateLiveConversionToggleMenuItem(newValue: self.liveConversionEnabled)
        self.updateTransformSelectedTextMenuItemEnabledState()
        // ピン留めプロンプトのキャッシュを更新
        self.reloadPinnedPromptsCache()
        self.pendingConverterServerActivation = ConverterSessionActivation(
            config: self.converterServerSessionConfig,
            inputLanguage: self.inputLanguage
        )

        if let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: Config.KeyboardLayout().value.layoutIdentifier)
        }
        // Chromium 系アプリで JS コンパイル中に activate された場合、
        // client.attributes(forCharacterIndex:) の同期呼び出しが deadlock を
        // 引き起こすため呼び出さない（Chromium issue 503787240）。
        // refreshCandidateWindow / refreshPredictionWindow は composing/selecting 状態で
        // client.attributes(...) を呼ぶ経路があるため、activate 中は使わずウィンドウを
        // 明示的に閉じる。
        self.candidatesViewController.updateCandidatePresentations([], selectionIndex: nil, cursorLocation: .zero)
        self.candidatesWindow.setIsVisible(false)
        self.candidatesWindow.orderOut(nil)
        self.candidatesViewController.hide()
        self.hidePredictionWindow()
    }

    @MainActor
    override func deactivateServer(_ sender: Any!) {
        self.activationGeneration &+= 1
        self.pendingConverterServerActivation = nil
        self.converterServerClient.sendIfSessionOpen({ _ in .lifecycle(.deactivate) }, completion: { _ in })
        self.currentConverterView = nil
        self.inputState = .none
        self.candidatesWindow.orderOut(nil)
        self.predictionWindow.orderOut(nil)
        self.replaceSuggestionWindow.orderOut(nil)
        self.candidatesViewController.updateCandidatePresentations([], selectionIndex: nil, cursorLocation: .zero)
        super.deactivateServer(sender)
    }

    @MainActor
    override func commitComposition(_ sender: Any!) {
        let activationGeneration = self.activationGeneration
        self.converterServerClient.sendIfSessionOpen({ _ in .composition(.commit) }, completion: { [weak self] response in
            Task { @MainActor in
                guard let self,
                      self.activationGeneration == activationGeneration,
                      let response else {
                    return
                }
                self.apply(response)
            }
        })
    }

    // MARK: - setValue: 状態同期のみ
    @MainActor
    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        defer {
            super.setValue(value, forTag: tag, client: sender)
        }

        if let value = value as? NSString {
            self.client()?.overrideKeyboard(withKeyboardNamed: Config.KeyboardLayout().value.layoutIdentifier)
            let englishMode = value == "com.apple.inputmethod.Roman"

            if englishMode {
                // 英語モードへの切り替え通知（実際の処理はhandleで行う）
                // メニューバーやshortcut経由の切り替えに対応する。
                // composing中でも英数キーMarkedTextを保ったまま英語入力へ移る。
                if self.inputLanguage == .japanese {
                    self.inputLanguage = .english
                    self.converterServerClient.send(
                        { _ in .lifecycle(.synchronizeInputLanguage(.english)) },
                        completion: { _ in }
                    )
                    self.refreshCandidateWindow()
                    self.refreshPredictionWindow()
                }
            } else {
                // 日本語モードへの切り替え
                if self.inputLanguage == .english {
                    self.inputLanguage = .japanese
                    self.converterServerClient.send(
                        { _ in .lifecycle(.synchronizeInputLanguage(.japanese)) },
                        completion: { _ in }
                    )
                }
            }
        }
    }

    override func menu() -> NSMenu! {
        self.appMenu
    }

    // swiftlint:disable:next cyclomatic_complexity
    @MainActor override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? IMKTextInput else {
            return false
        }
        guard event.type == .keyDown else {
            return false
        }

        // カスタムプロンプトショートカットのチェック
        if let matchedPrompt = checkCustomPromptShortcut(event: event) {
            let aiBackendEnabled = Config.AIBackendPreference().value != .off
            if aiBackendEnabled && !self.isPromptWindowVisible {
                let selectedRange = client.selectedRange()
                if selectedRange.length > 0 {
                    if self.triggerAiTranslation(initialPrompt: matchedPrompt) {
                        return true
                    }
                }
            }
            // ショートカットがマッチした場合はイベントを消費して他のハンドラに渡さない
            return true
        }

        let userAction = UserAction.getUserAction(eventCore: event.keyEventCore, inputLanguage: inputLanguage)

        // 英数キー（keyCode 102）の処理
        if event.keyCode == 102 {
            let isDoubleTap = checkAndUpdateDoubleTap(keyCode: 102)

            if isDoubleTap {
                let selectedRange = client.selectedRange()
                if selectedRange.length > 0 {
                    if self.triggerAiTranslation(initialPrompt: "english") {
                        return true
                    }
                }
            }
        }

        // かなキー（keyCode 104）の処理（ダブルタップで日本語への翻訳）
        if event.keyCode == 104 {
            let isDoubleTap = checkAndUpdateDoubleTap(keyCode: 104)
            if isDoubleTap {
                let selectedRange = client.selectedRange()
                if selectedRange.length > 0 {
                    if self.triggerAiTranslation(initialPrompt: "japanese") {
                        return true
                    }
                }
            }
        }

        // Check if AI backend is enabled
        let aiBackendEnabled = Config.AIBackendPreference().value != .off

        // Handle suggest action with selected text check (prevent recursive calls)
        if case .suggest = userAction {
            // Prevent recursive window calls
            if self.isPromptWindowVisible {
                self.appendDebugMessage("Suggest action ignored: prompt window already visible")
                return true
            }

            let selectedRange = client.selectedRange()
            self.appendDebugMessage("Suggest action detected. Selected range: \(selectedRange)")
            if selectedRange.length > 0 {
                guard aiBackendEnabled else {
                    self.appendDebugMessage("Suggest action ignored: AI backend is off")
                    return false
                }
                self.appendDebugMessage("Selected text found, showing prompt input window")
                // There is selected text, show prompt input window
                self.showPromptInputWindow()
                return true
            } else {
                self.appendDebugMessage("No selected text, using normal suggest behavior")
            }
        }

        return self.handleKeyEventWithConverterServer(
            event: event.keyEventCore,
            enableSuggestion: aiBackendEnabled,
            optionDirectInputText: event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.option))
        )
    }

    @MainActor
    private func handleKeyEventWithConverterServer(
        event: KeyEventCore,
        enableSuggestion: Bool,
        optionDirectInputText: String? = nil
    ) -> Bool {
        let disposition = ConverterClientEventRouter.disposition(
            event: event,
            context: .init(
                acknowledgedInputState: ConverterInputState(self.inputState),
                acknowledgedInputLanguage: self.inputLanguage,
                hasPendingKeyEvents: self.pendingKeyEventCount > 0,
                liveConversionEnabled: Config.LiveConversion().value,
                enableDebugWindow: Config.DebugWindow().value,
                enableSuggestion: enableSuggestion,
                typeBackSlash: Config.TypeBackSlash().value
            )
        )
        guard disposition == .sendToServer else {
            return false
        }

        self.nextKeyEventID &+= 1
        let request = ConverterKeyEventRequest(
            eventID: self.nextKeyEventID,
            event: event,
            inputStyle: self.inputStyle,
            liveConversionEnabled: Config.LiveConversion().value,
            enableDebugWindow: Config.DebugWindow().value,
            enableSuggestion: enableSuggestion,
            enablePredictiveTyping: Config.DebugPredictiveTyping().value,
            enableTypoCorrection: Config.DebugTypoCorrection().value,
            enableOptionDirectFullWidthInput: Config.OptionDirectFullWidthInput().value,
            typeBackSlash: Config.TypeBackSlash().value,
            optionDirectInputText: optionDirectInputText,
            context: self.currentConverterTextContext(),
            activation: self.pendingConverterServerActivation
        )
        self.pendingConverterServerActivation = nil
        self.pendingKeyEventCount += 1
        let activationGeneration = self.activationGeneration
        self.converterServerClient.sendKeyEvent(request) { [weak self] response in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.pendingKeyEventCount = max(0, self.pendingKeyEventCount - 1)
                guard self.activationGeneration == activationGeneration else {
                    return
                }
                guard let response else {
                    self.appendDebugMessage("ConverterServer dropped key event \(request.eventID)")
                    return
                }
                if !response.handled {
                    // `handle` は既に同期的に consume 済み。未応答イベントがある場合は
                    // application へ後からイベントを戻せないため、ここでは漏らさない。
                    self.appendDebugMessage("Consumed delayed fallthrough event \(request.eventID)")
                }
                self.apply(response)
            }
        }
        return true
    }

    @MainActor
    func requestPredictiveSuggestionWithConverterServer(client: IMKTextInput) -> Bool {
        self.handleKeyEventWithConverterServer(
            event: KeyEventCore(
                modifierFlags: [.control],
                characters: "s",
                charactersIgnoringModifiers: "s",
                keyCode: 1
            ),
            enableSuggestion: Config.AIBackendPreference().value != .off
        )
    }

    @MainActor
    private func apply(_ response: ConverterServerResponse) {
        if let inputLanguage = response.inputLanguage {
            self.inputLanguage = inputLanguage
        }
        self.inputState = response.inputState.inputState
        self.currentConverterView = response.snapshot
        if let client = self.client() {
            for effect in response.effects {
                self.apply(effect, client: client)
            }
        }
        self.refreshMarkedText()
        self.refreshCandidateWindow()
        self.refreshPredictionWindow()
        self.refreshReplaceSuggestionWindow()
    }

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    private func apply(_ effect: ConverterClientEffect, client: IMKTextInput) {
        switch effect {
        case .insertText(let text):
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        case .switchInputLanguage(let language):
            self.switchInputLanguage(language, client: client)
        case .requestPredictiveSuggestion:
            self.requestReplaceSuggestion()
        case .requestReplaceSuggestion:
            self.requestReplaceSuggestion()
        case .selectNextReplaceSuggestionCandidate:
            self.selectReplaceSuggestionCandidate(offset: 1)
        case .selectPreviousReplaceSuggestionCandidate:
            self.selectReplaceSuggestionCandidate(offset: -1)
        case .submitReplaceSuggestionCandidate:
            self.submitSelectedSuggestionCandidate()
        case .hideReplaceSuggestionWindow:
            self.replaceSuggestionWindow.setIsVisible(false)
            self.replaceSuggestionWindow.orderOut(nil)
        case .showPromptInputWindow:
            self.showPromptInputWindow()
        case .transformSelectedText(let selectedText, let prompt):
            self.transformSelectedText(selectedText: selectedText, prompt: prompt)
        case .fallthroughToApplication:
            break
        }
    }

    private var inputStyle: ConverterInputStyle {
        switch Config.InputStyle().value {
        case .default:
            .defaultRomanToKana
        case .defaultAZIK:
            .defaultAZIK
        case .defaultKanaUS:
            .defaultKanaUS
        case .defaultKanaJIS:
            .defaultKanaJIS
        case .custom:
            .tableName(CustomInputTableStore.tableName)
        }
    }

    private var converterServerSessionConfig: ConverterSessionConfig {
        ConverterSessionConfig(
            aiBackendPreference: Config.AIBackendPreference().value,
            openAIModelName: Config.OpenAiModelName().value,
            openAIEndpoint: Config.OpenAiApiEndpoint().value,
            openAIAPIKey: .init(Config.OpenAiApiKey().value),
            includeContextInAITransform: Config.IncludeContextInAITransform().value
        )
    }

    @MainActor
    private func syncConverterServerSessionConfig() {
        let config = self.converterServerSessionConfig
        self.converterServerClient.send(
            { _ in .updateConfig(config) },
            completion: { _ in }
        )
    }

    @MainActor func switchInputLanguage(_ language: InputLanguage, client: IMKTextInput) {
        self.inputLanguage = language
        client.overrideKeyboard(withKeyboardNamed: Config.KeyboardLayout().value.layoutIdentifier)
        switch language {
        case .english:
            client.selectMode("dev.ensan.inputmethod.azooKeyMac.Roman")
        case .japanese:
            client.selectMode("dev.ensan.inputmethod.azooKeyMac.Japanese")
        }
    }

    @MainActor
    private func discardConverterServerComposition() {
        self.currentConverterView = nil
        self.converterServerClient.sendIfSessionOpen(
            { _ in .composition(.stopComposition) },
            completion: { _ in }
        )
    }

    func refreshCandidateWindow() {
        if let currentConverterView {
            self.refreshCandidateWindow(currentConverterView.candidateWindow)
            return
        }
        self.candidatesWindow.setIsVisible(false)
        self.candidatesWindow.orderOut(nil)
        self.candidatesViewController.hide()
    }

    private func refreshCandidateWindow(_ candidateWindow: ConverterCandidateWindow) {
        switch candidateWindow {
        case .selecting(let candidates, let selectionIndex):
            var rect: NSRect = .zero
            self.client().attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
            self.candidatesViewController.showCandidateIndex = true
            self.candidatesViewController.updateCandidatePresentations(
                candidates,
                selectionIndex: selectionIndex,
                cursorLocation: rect.origin
            )
            self.candidatesWindow.orderFront(nil)
        case .composing(let candidates, let selectionIndex):
            var rect: NSRect = .zero
            self.client().attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
            self.candidatesViewController.showCandidateIndex = false
            self.candidatesViewController.updateCandidatePresentations(
                candidates,
                selectionIndex: selectionIndex,
                cursorLocation: rect.origin
            )
            self.candidatesWindow.orderFront(nil)
        case .hidden:
            self.candidatesWindow.setIsVisible(false)
            self.candidatesWindow.orderOut(nil)
            self.candidatesViewController.hide()
        }
    }

    @MainActor private func refreshReplaceSuggestionWindow() {
        guard self.inputState == .replaceSuggestion,
              let currentConverterView,
              !currentConverterView.replaceSuggestionCandidates.isEmpty else {
            self.replaceSuggestionsViewController.updateCandidatePresentations([], selectionIndex: nil, cursorLocation: .zero)
            self.replaceSuggestionWindow.setIsVisible(false)
            self.replaceSuggestionWindow.orderOut(nil)
            return
        }
        self.replaceSuggestionsViewController.updateCandidatePresentations(
            currentConverterView.replaceSuggestionCandidates,
            selectionIndex: currentConverterView.replaceSuggestionSelectionIndex,
            cursorLocation: self.getCursorLocation()
        )
        self.replaceSuggestionWindow.setIsVisible(true)
        self.replaceSuggestionWindow.makeKeyAndOrderFront(nil)
    }

    @MainActor private func selectReplaceSuggestionCandidate(offset: Int) {
        guard let view = self.currentConverterView,
              !view.replaceSuggestionCandidates.isEmpty else {
            return
        }
        let count = view.replaceSuggestionCandidates.count
        let current = view.replaceSuggestionSelectionIndex ?? (offset > 0 ? -1 : 0)
        let next = (current + offset + count) % count
        self.converterServerClient.sendIfSessionOpen(
            { _ in .replaceSuggestion(.selectReplaceSuggestionCandidate(index: next)) },
            completion: { [weak self] response in
                Task { @MainActor in
                    guard let self, let response else {
                        return
                    }
                    self.apply(response)
                }
            }
        )
    }

    @MainActor private func showReplaceSuggestionError(message: String) {
        self.appendDebugMessage("APIリクエストエラー: \(message)")
        let alert = NSAlert()
        alert.messageText = "変換に失敗しました"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func refreshPredictionWindow() {
        guard self.inputState == .composing else {
            self.hidePredictionWindow()
            return
        }

        guard let predictions = self.currentConverterView?.predictionCandidates else {
            self.hidePredictionWindow()
            return
        }
        if predictions.isEmpty {
            let now = Date().timeIntervalSince1970
            let elapsed = now - self.lastPredictionUpdateTime
            if elapsed < 1.0, !self.lastPredictionCandidates.isEmpty {
                self.showCachedPredictionWindow()
                self.schedulePredictionHide(after: max(0, 1.0 - elapsed))
                return
            }
            self.hidePredictionWindow()
            return
        }

        self.predictionHideWorkItem?.cancel()
        let candidates = predictions.map { ConverterCandidatePresentation(text: $0.displayText) }

        self.lastPredictionCandidates = predictions.map(\.displayText)
        self.lastPredictionUpdateTime = Date().timeIntervalSince1970

        var rect: NSRect = .zero
        self.client().attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        self.predictionViewController.updateCandidatePresentations(
            candidates,
            selectionIndex: nil,
            cursorLocation: rect.origin
        )

        if Config.LiveConversion().value {
            self.predictionWindow.orderFront(nil)
            return
        }

        if self.candidatesWindow.isVisible {
            self.positionPredictionWindowRightOfCandidateWindow()
        }
        self.predictionWindow.orderFront(nil)
    }

    private func positionPredictionWindowRightOfCandidateWindow(gap: CGFloat = 8) {
        // アンカーである候補ウィンドウの中心が乗っているスクリーンを基準にする。
        // predictionWindow.screen / candidatesWindow.screen はマルチディスプレイ遷移直後に
        // 古いディスプレイを返すことがあるため、frame の中心点で能動的に判定する。
        let anchorFrame = self.candidatesWindow.frame
        let anchorCenter = CGPoint(x: anchorFrame.midX, y: anchorFrame.midY)
        guard let screen = ScreenLookup.screen(containing: anchorCenter, fallbackWindow: self.candidatesWindow) else {
            return
        }

        let frame = WindowPositioning.frameRightOfAnchor(
            currentFrame: WindowPositioning.Rect(self.predictionWindow.frame),
            anchorFrame: WindowPositioning.Rect(anchorFrame),
            screenRect: WindowPositioning.Rect(screen.visibleFrame),
            gap: Double(gap)
        )
        self.predictionWindow.setFrame(frame.cgRect, display: true)
    }

    private func showCachedPredictionWindow() {
        let candidates = self.lastPredictionCandidates.map { ConverterCandidatePresentation(text: $0) }
        guard !candidates.isEmpty else {
            return
        }
        var rect: NSRect = .zero
        self.client().attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        self.predictionViewController.updateCandidatePresentations(
            candidates,
            selectionIndex: nil,
            cursorLocation: rect.origin
        )
        self.predictionWindow.orderFront(nil)
    }

    private func schedulePredictionHide(after delay: TimeInterval) {
        self.predictionHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            let now = Date().timeIntervalSince1970
            if now - self.lastPredictionUpdateTime >= 1.0 {
                self.hidePredictionWindow()
            }
        }
        self.predictionHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func hidePredictionWindow() {
        self.predictionWindow.setIsVisible(false)
        self.predictionWindow.orderOut(nil)
        self.lastPredictionCandidates = []
        self.lastPredictionUpdateTime = 0
        self.predictionHideWorkItem?.cancel()
        self.predictionHideWorkItem = nil
    }

    var retryCount = 0
    let maxRetries = 3

    @MainActor func handleSuggestionError(_ error: Error, cursorPosition: CGPoint) {
        let errorMessage = "エラーが発生しました: \(error.localizedDescription)"
        self.appendDebugMessage(errorMessage)
    }

    func getCursorLocation() -> CGPoint {
        var rect: NSRect = .zero
        self.client()?.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        self.appendDebugMessage("カーソル位置取得: \(rect.origin)")
        return rect.origin
    }

    func refreshMarkedText() {
        let highlight = self.mark(
            forStyle: kTSMHiliteSelectedConvertedText,
            at: NSRange(location: NSNotFound, length: 0)
        ) as? [NSAttributedString.Key: Any]
        let underline = self.mark(
            forStyle: kTSMHiliteConvertedText,
            at: NSRange(location: NSNotFound, length: 0)
        ) as? [NSAttributedString.Key: Any]
        let text = NSMutableAttributedString(string: "")
        let currentMarkedText = self.currentMarkedText()
        for part in currentMarkedText.elements where !part.content.isEmpty {
            let attributes: [NSAttributedString.Key: Any]? = switch part.focus {
            case .focused: highlight
            case .unfocused: underline
            case .none: [:]
            }
            text.append(
                NSAttributedString(
                    string: part.content,
                    attributes: attributes
                )
            )
        }
        self.client()?.setMarkedText(
            text,
            selectionRange: currentMarkedText.selectionRange.nsRange,
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    private func currentMarkedText() -> ConverterMarkedText {
        if let currentConverterView {
            return currentConverterView.markedText
        }
        return ConverterSessionSnapshot.empty.markedText
    }
}

extension azooKeyMacInputController: CandidatesViewControllerDelegate {
    func candidateSubmitted() {
        Task { @MainActor in
            guard self.currentConverterView != nil else {
                return
            }
            self.converterServerClient.sendIfSessionOpen(
                { _ in .candidate(.submitSelectedCandidate(context: self.currentConverterTextContext())) },
                completion: { [weak self] response in
                    Task { @MainActor in
                        guard let self, let response else {
                            return
                        }
                        self.apply(response)
                    }
                }
            )
        }
    }

    func candidateSelectionChanged(_ row: Int) {
        Task { @MainActor in
            guard self.currentConverterView != nil else {
                return
            }
            self.converterServerClient.sendIfSessionOpen(
                { _ in .candidate(.selectCandidate(index: row)) },
                completion: { [weak self] response in
                    Task { @MainActor in
                        guard let self, let response else {
                            return
                        }
                        self.apply(response)
                    }
                }
            )
        }
    }
}

extension azooKeyMacInputController {
    private func currentConverterTextContext() -> ConverterTextContext {
        ConverterTextContext(
            leftSideContext: self.getLeftSideContext(),
            rightSideContext: self.getRightSideContext()
        )
    }

    func getLeftSideContext(maxCount: Int = ConverterTextContext.transportCharacterLimit) -> String? {
        let endIndex = self.contextRange().location
        let leftRange = NSRange(location: max(endIndex - maxCount, 0), length: min(endIndex, maxCount))
        var actual = NSRange()
        // 同じ行の文字のみコンテキストに含める
        let leftSideContext = self.client().string(from: leftRange, actualRange: &actual)
        self.appendDebugMessage("\(#function): leftSideContext=\(leftSideContext ?? "nil")")
        return leftSideContext
    }

    func getRightSideContext(maxCount: Int = ConverterTextContext.transportCharacterLimit) -> String? {
        let range = self.contextRange()
        let startIndex = range.location + range.length
        let documentLength = self.client().length()
        guard startIndex < documentLength else {
            return nil
        }
        let rightRange = NSRange(location: startIndex, length: min(documentLength - startIndex, maxCount))
        var actual = NSRange()
        let rightSideContext = self.client().string(from: rightRange, actualRange: &actual)
        self.appendDebugMessage("\(#function): rightSideContext=\(rightSideContext ?? "nil")")
        return rightSideContext
    }

    private func contextRange() -> NSRange {
        let markedRange = self.client().markedRange()
        if markedRange.location != NSNotFound {
            return markedRange
        }
        let selectedRange = self.client().selectedRange()
        if selectedRange.location != NSNotFound {
            return selectedRange
        }
        return NSRange(location: 0, length: 0)
    }
}

extension azooKeyMacInputController: ReplaceSuggestionsViewControllerDelegate {
    @MainActor func replaceSuggestionSelectionChanged(_ row: Int) {
        guard self.currentConverterView?.replaceSuggestionSelectionIndex != row else {
            return
        }
        self.converterServerClient.sendIfSessionOpen(
            { _ in .replaceSuggestion(.selectReplaceSuggestionCandidate(index: row)) },
            completion: { [weak self] response in
                Task { @MainActor in
                    guard let self, let response else {
                        return
                    }
                    self.apply(response)
                }
            }
        )
    }

    func replaceSuggestionSubmitted() {
        Task { @MainActor in
            self.submitSelectedSuggestionCandidate()
        }
    }
}

// Suggest Candidate
extension azooKeyMacInputController {
    // MARK: - Replace Suggestion Request Handling
    @MainActor func requestReplaceSuggestion() {
        self.appendDebugMessage("requestReplaceSuggestion: 開始")

        // リクエスト開始時に前回の候補をクリアし、ウィンドウを非表示にする
        self.replaceSuggestionsViewController.updateCandidatePresentations([], selectionIndex: nil, cursorLocation: .zero)
        self.replaceSuggestionWindow.setIsVisible(false)
        self.replaceSuggestionWindow.orderOut(nil)

        guard let currentConverterView, !currentConverterView.isEmpty else {
            self.appendDebugMessage("requestReplaceSuggestion: skipped because converter server composition is empty")
            return
        }
        self.syncConverterServerSessionConfig()
        self.converterServerClient.sendIfSessionOpen(
            { _ in .replaceSuggestion(.request(context: self.currentConverterTextContext())) },
            completion: { [weak self] response in
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    guard let response else {
                        self.showReplaceSuggestionError(message: "ConverterServerから候補を取得できませんでした")
                        return
                    }
                    guard self.currentConverterView?.convertTarget == response.snapshot.convertTarget else {
                        self.appendDebugMessage("候補ウィンドウ更新をスキップ: composition changed")
                        return
                    }
                    self.currentConverterView = response.snapshot
                    self.inputState = response.inputState.inputState
                    self.refreshMarkedText()
                    self.refreshReplaceSuggestionWindow()
                }
            }
        )
        self.appendDebugMessage("requestReplaceSuggestion: 終了")
    }

    // MARK: - Window Management
    @MainActor func hideReplaceSuggestionCandidateView() {
        self.replaceSuggestionWindow.setIsVisible(false)
        self.replaceSuggestionWindow.orderOut(nil)
    }

    @MainActor func submitSelectedSuggestionCandidate() {
        self.converterServerClient.sendIfSessionOpen(
            { _ in .replaceSuggestion(.submitSelectedReplaceSuggestion) },
            completion: { [weak self] response in
                Task { @MainActor in
                    guard let self, let response else {
                        return
                    }
                    self.apply(response)
                }
            }
        )
    }

    @MainActor private func finishReplaceSuggestionComposition() {
        if self.currentConverterView != nil {
            self.discardConverterServerComposition()
        }
        self.inputState = .none
        self.refreshMarkedText()
        self.refreshCandidateWindow()
        self.refreshPredictionWindow()
        self.refreshReplaceSuggestionWindow()
    }

    // MARK: - Helper Methods
    private func retrySuggestionRequestIfNeeded(cursorPosition: CGPoint) {
        if retryCount < maxRetries {
            retryCount += 1
            self.appendDebugMessage("再試行中... (\(retryCount)回目)")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.requestReplaceSuggestion()
            }
        } else {
            self.appendDebugMessage("再試行上限に達しました。")
            retryCount = 0
        }
    }

}
