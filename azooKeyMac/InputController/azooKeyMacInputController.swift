import Cocoa
import Core
import InputMethodKit
import KanaKanjiConverterModuleWithDefaultDictionary

@objc(azooKeyMacInputController)
class azooKeyMacInputController: IMKInputController { // swiftlint:disable:this type_name
    var segmentsManager: SegmentsManager
    private var inputState: InputState = .none
    private var inputLanguage: InputLanguage = .japanese
    var zenzaiEnabled: Bool {
        Config.ZenzaiIntegration().value
    }
    var liveConversionEnabled: Bool {
        Config.LiveConversion().value
    }

    var appMenu: NSMenu
    var zenzaiToggleMenuItem: NSMenuItem
    var liveConversionToggleMenuItem: NSMenuItem

    private var candidatesWindow: NSWindow
    private var candidatesViewController: CandidatesViewController

    private var replaceSuggestionWindow: NSWindow
    private var replaceSuggestionsViewController: ReplaceSuggestionsViewController

    private var promptInputWindow: PromptInputWindow
    private var isPromptWindowVisible: Bool = false

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        self.segmentsManager = SegmentsManager()

        self.appMenu = NSMenu(title: "azooKey")
        self.zenzaiToggleMenuItem = NSMenuItem()
        self.liveConversionToggleMenuItem = NSMenuItem()

        // Initialize the candidates window
        self.candidatesViewController = CandidatesViewController()
        self.candidatesWindow = NSWindow(contentViewController: self.candidatesViewController)
        self.candidatesWindow.styleMask = [.borderless]
        self.candidatesWindow.level = .popUpMenu

        var rect: NSRect = .zero
        if let client = inputClient as? IMKTextInput {
            client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        }
        rect.size = .init(width: 400, height: 1000)
        self.candidatesWindow.setFrame(rect, display: true)
        // init直後はこれを表示しない
        self.candidatesWindow.setIsVisible(false)
        self.candidatesWindow.orderOut(nil)

        // ReplaceSuggestionsViewControllerの初期化
        self.replaceSuggestionsViewController = ReplaceSuggestionsViewController()
        self.replaceSuggestionWindow = NSWindow(contentViewController: self.replaceSuggestionsViewController)
        self.replaceSuggestionWindow.styleMask = [.borderless]
        self.replaceSuggestionWindow.level = .popUpMenu

        if let client = inputClient as? IMKTextInput {
            client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        }
        rect.size = .init(width: 400, height: 1000)
        self.replaceSuggestionWindow.setFrame(rect, display: true)
        self.replaceSuggestionWindow.setIsVisible(false)
        self.replaceSuggestionWindow.orderOut(nil)

        // PromptInputWindowの初期化
        self.promptInputWindow = PromptInputWindow()

        super.init(server: server, delegate: delegate, client: inputClient)

        // デリゲートの設定を super.init の後に移動
        self.candidatesViewController.delegate = self
        self.replaceSuggestionsViewController.delegate = self
        self.segmentsManager.delegate = self
        self.setupMenu()
    }

    @MainActor
    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        // アプリケーションサポートのディレクトリを準備しておく
        self.prepareApplicationSupportDirectory()
        self.updateZenzaiToggleMenuItem(newValue: self.zenzaiEnabled)
        self.updateLiveConversionToggleMenuItem(newValue: self.liveConversionEnabled)
        self.segmentsManager.activate()

        if let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.US")
            var rect: NSRect = .zero
            client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
            self.candidatesViewController.updateCandidates([], selectionIndex: nil, cursorLocation: rect.origin)
        } else {
            self.candidatesViewController.updateCandidates([], selectionIndex: nil, cursorLocation: .zero)
        }
        self.refreshCandidateWindow()
    }

    @MainActor
    override func deactivateServer(_ sender: Any!) {
        self.segmentsManager.deactivate()
        self.candidatesWindow.orderOut(nil)
        self.replaceSuggestionWindow.orderOut(nil)
        self.candidatesViewController.updateCandidates([], selectionIndex: nil, cursorLocation: .zero)
        if let client = sender as? IMKTextInput {
            client.insertText("", replacementRange: .notFound)
        }
        super.deactivateServer(sender)
    }

    @MainActor
    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        if let value = value as? NSString {
            self.client()?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.US")
            let englishMode = value == "com.apple.inputmethod.Roman"
            // 英数/かなの対応するキーが推された場合と同等のイベントを発生させる
            let userAction: UserAction? = if englishMode, self.inputLanguage != .english {
                .英数
            } else if !englishMode, self.inputLanguage == .english {
                .かな
            } else {
                nil
            }
            if let userAction {
                let (clientAction, clientActionCallback) = self.inputState.event(
                    eventCore: .init(modifierFlags: []),
                    userAction: userAction,
                    inputLanguage: self.inputLanguage,
                    liveConversionEnabled: false,
                    enableDebugWindow: false,
                    enableSuggestion: false
                )
                _ = self.handleClientAction(
                    clientAction,
                    clientActionCallback: clientActionCallback,
                    client: self.client()
                )
            }
        }
        super.setValue(value, forTag: tag, client: sender)
    }

    override func menu() -> NSMenu! {
        self.appMenu
    }

    private func isPrintable(_ text: String) -> Bool {
        let printable: CharacterSet = [.alphanumerics, .symbols, .punctuationCharacters]
            .reduce(into: CharacterSet()) {
                $0.formUnion($1)
            }
        return CharacterSet(text.unicodeScalars).isSubset(of: printable)
    }

    @MainActor override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? IMKTextInput else {
            return false
        }
        guard event.type == .keyDown else {
            return false
        }

        let userAction = UserAction.getUserAction(event: event, inputLanguage: inputLanguage)

        // Handle suggest action with selected text check (prevent recursive calls)
        if case .suggest = userAction {
            // Prevent recursive window calls
            if self.isPromptWindowVisible {
                self.segmentsManager.appendDebugMessage("Suggest action ignored: prompt window already visible")
                return true
            }

            let selectedRange = client.selectedRange()
            self.segmentsManager.appendDebugMessage("Suggest action detected. Selected range: \(selectedRange)")
            if selectedRange.length > 0 {
                self.segmentsManager.appendDebugMessage("Selected text found, showing prompt input window")
                // There is selected text, show prompt input window
                return self.handleClientAction(.showPromptInputWindow, clientActionCallback: .fallthrough, client: client)
            } else {
                self.segmentsManager.appendDebugMessage("No selected text, using normal suggest behavior")
            }
        }

        let (clientAction, clientActionCallback) = inputState.event(
            event,
            userAction: userAction,
            inputLanguage: self.inputLanguage,
            liveConversionEnabled: Config.LiveConversion().value,
            enableDebugWindow: Config.DebugWindow().value,
            enableSuggestion: Config.EnableOpenAiApiKey().value
        )
        return handleClientAction(clientAction, clientActionCallback: clientActionCallback, client: client)
    }

    // この種のコードは複雑にしかならないので、lintを無効にする
    // swiftlint:disable:next cyclomatic_complexity
    @MainActor func handleClientAction(_ clientAction: ClientAction, clientActionCallback: ClientActionCallback, client: IMKTextInput) -> Bool {
        // return only false
        switch clientAction {
        case .showCandidateWindow:
            self.segmentsManager.requestSetCandidateWindowState(visible: true)
        case .hideCandidateWindow:
            self.segmentsManager.requestSetCandidateWindowState(visible: false)
        case .enterFirstCandidatePreviewMode:
            self.segmentsManager.requestSetCandidateWindowState(visible: false)
        case .enterCandidateSelectionMode:
            self.segmentsManager.update(requestRichCandidates: true)
        case .appendToMarkedText(let string):
            self.segmentsManager.insertAtCursorPosition(string, inputStyle: .roman2kana)
        case .insertWithoutMarkedText(let string):
            client.insertText(string, replacementRange: NSRange(location: NSNotFound, length: 0))
        case .editSegment(let count):
            self.segmentsManager.editSegment(count: count)
        case .commitMarkedText:
            let text = self.segmentsManager.commitMarkedText(inputState: self.inputState)
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        case .commitMarkedTextAndAppendToMarkedText(let string):
            let text = self.segmentsManager.commitMarkedText(inputState: self.inputState)
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            self.segmentsManager.insertAtCursorPosition(string, inputStyle: .roman2kana)
        case .submitSelectedCandidate:
            self.submitSelectedCandidate()
        case .submitSelectedCandidateAndAppendToMarkedText(let string):
            self.submitSelectedCandidate()
            self.segmentsManager.insertAtCursorPosition(string, inputStyle: .roman2kana)
        case .submitSelectedCandidateAndEnterFirstCandidatePreviewMode:
            self.submitSelectedCandidate()
            self.segmentsManager.requestSetCandidateWindowState(visible: false)
        case .removeLastMarkedText:
            self.segmentsManager.deleteBackwardFromCursorPosition()
            self.segmentsManager.requestResettingSelection()
        case .selectPrevCandidate:
            self.segmentsManager.requestSelectingPrevCandidate()
        case .selectNextCandidate:
            self.segmentsManager.requestSelectingNextCandidate()
        case .selectNumberCandidate(let num):
            self.segmentsManager.requestSelectingRow(self.candidatesViewController.getNumberCandidate(num: num))
            self.submitSelectedCandidate()
            self.segmentsManager.requestResettingSelection()
        case .submitHiraganaCandidate:
            self.submitCandidate(self.segmentsManager.getModifiedRubyCandidate {
                $0.toHiragana()
            })
        case .submitKatakanaCandidate:
            self.submitCandidate(self.segmentsManager.getModifiedRubyCandidate {
                $0.toKatakana()
            })
        case .submitHankakuKatakanaCandidate:
            self.submitCandidate(self.segmentsManager.getModifiedRubyCandidate {
                $0.toKatakana().applyingTransform(.fullwidthToHalfwidth, reverse: false)!
            })
        case .enableDebugWindow:
            self.segmentsManager.requestDebugWindowMode(enabled: true)
        case .disableDebugWindow:
            self.segmentsManager.requestDebugWindowMode(enabled: false)
        case .stopComposition:
            self.segmentsManager.stopComposition()
        case .forgetMemory:
            self.segmentsManager.forgetMemory()
        case .selectInputLanguage(let language):
            self.inputLanguage = language
            self.switchInputLanguage(language, client: client)
        case .commitMarkedTextAndSelectInputLanguage(let language):
            let text = self.segmentsManager.commitMarkedText(inputState: self.inputState)
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            self.inputLanguage = language
            self.switchInputLanguage(language, client: client)
        // PredictiveSuggestion
        case .requestPredictiveSuggestion:
            // 「つづき」を直接入力し、コンテキストを渡す
            self.segmentsManager.insertAtCursorPosition("つづき", inputStyle: .roman2kana)
            self.requestReplaceSuggestion()
        // ReplaceSuggestion
        case .requestReplaceSuggestion:
            self.requestReplaceSuggestion()
        case .selectNextReplaceSuggestionCandidate:
            self.replaceSuggestionsViewController.selectNextCandidate()
        case .selectPrevReplaceSuggestionCandidate:
            self.replaceSuggestionsViewController.selectPrevCandidate()
        case .submitReplaceSuggestionCandidate:
            self.submitSelectedSuggestionCandidate()
        case .hideReplaceSuggestionWindow:
            self.replaceSuggestionWindow.setIsVisible(false)
            self.replaceSuggestionWindow.orderOut(nil)
        // Selected Text Transform
        case .showPromptInputWindow:
            self.segmentsManager.appendDebugMessage("Executing showPromptInputWindow")
            self.showPromptInputWindow()
        case .transformSelectedText(let selectedText, let prompt):
            self.segmentsManager.appendDebugMessage("Executing transformSelectedText with text: '\(selectedText)' and prompt: '\(prompt)'")
            self.transformSelectedText(selectedText: selectedText, prompt: prompt)
        // MARK: 特殊ケース
        case .consume:
            // 何もせず先に進む
            break
        case .fallthrough:
            return false
        }

        switch clientActionCallback {
        case .fallthrough:
            break
        case .transition(let inputState):
            // 遷移した時にreplaceSuggestionWindowをhideする
            if inputState != .replaceSuggestion {
                self.replaceSuggestionWindow.orderOut(nil)
            }
            if inputState == .none {
                self.switchInputLanguage(self.inputLanguage, client: client)
            }
            self.inputState = inputState
        case .basedOnBackspace(let ifIsEmpty, let ifIsNotEmpty), .basedOnSubmitCandidate(let ifIsEmpty, let ifIsNotEmpty):
            self.inputState = self.segmentsManager.isEmpty ? ifIsEmpty : ifIsNotEmpty
        }

        self.refreshMarkedText()
        self.refreshCandidateWindow()
        return true
    }

    @MainActor func switchInputLanguage(_ language: InputLanguage, client: IMKTextInput) {
        client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.US")
        switch language {
        case .english:
            client.selectMode("dev.ensan.inputmethod.azooKeyMac.Roman")
            self.segmentsManager.stopJapaneseInput()
        case .japanese:
            client.selectMode("dev.ensan.inputmethod.azooKeyMac.Japanese")
        }
    }

    func refreshCandidateWindow() {
        switch self.segmentsManager.getCurrentCandidateWindow(inputState: self.inputState) {
        case .selecting(let candidates, let selectionIndex):
            var rect: NSRect = .zero
            self.client().attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
            self.candidatesViewController.showCandidateIndex = true
            self.candidatesViewController.updateCandidates(candidates, selectionIndex: selectionIndex, cursorLocation: rect.origin)
            self.candidatesWindow.orderFront(nil)
        case .composing(let candidates, let selectionIndex):
            var rect: NSRect = .zero
            self.client().attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
            self.candidatesViewController.showCandidateIndex = false
            self.candidatesViewController.updateCandidates(candidates, selectionIndex: selectionIndex, cursorLocation: rect.origin)
            self.candidatesWindow.orderFront(nil)
        case .hidden:
            self.candidatesWindow.setIsVisible(false)
            self.candidatesWindow.orderOut(nil)
            self.candidatesViewController.hide()
        }
    }

    var retryCount = 0
    let maxRetries = 3

    @MainActor func handleSuggestionError(_ error: Error, cursorPosition: CGPoint) {
        let errorMessage = "エラーが発生しました: \(error.localizedDescription)"
        self.segmentsManager.appendDebugMessage(errorMessage)
    }

    func getCursorLocation() -> CGPoint {
        var rect: NSRect = .zero
        self.client()?.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        self.segmentsManager.appendDebugMessage("カーソル位置取得: \(rect.origin)")
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
        let currentMarkedText = self.segmentsManager.getCurrentMarkedText(inputState: self.inputState)
        for part in currentMarkedText where !part.content.isEmpty {
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
            selectionRange: currentMarkedText.selectionRange,
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    @MainActor
    func submitCandidate(_ candidate: Candidate) {
        if let client = self.client() {
            // インサートを行う前にコンテキストを取得する
            let cleanLeftSideContext = self.segmentsManager.getCleanLeftSideContext(maxCount: 30)
            client.insertText(candidate.text, replacementRange: NSRange(location: NSNotFound, length: 0))
            // アプリケーションサポートのディレクトリを準備しておく
            self.segmentsManager.prefixCandidateCommited(candidate, leftSideContext: cleanLeftSideContext ?? "")
        }
    }

    @MainActor
    func submitSelectedCandidate() {
        if let candidate = self.segmentsManager.selectedCandidate {
            self.submitCandidate(candidate)
            self.segmentsManager.requestResettingSelection()
        }
    }
}

extension azooKeyMacInputController: CandidatesViewControllerDelegate {
    func candidateSubmitted() {
        Task { @MainActor in
            self.submitSelectedCandidate()
        }
    }

    func candidateSelectionChanged(_ row: Int) {
        Task { @MainActor in
            self.segmentsManager.requestSelectingRow(row)
        }
    }
}

extension azooKeyMacInputController: SegmentManagerDelegate {
    func getLeftSideContext(maxCount: Int) -> String? {
        let endIndex = client().markedRange().location
        let leftRange = NSRange(location: max(endIndex - maxCount, 0), length: min(endIndex, maxCount))
        var actual = NSRange()
        // 同じ行の文字のみコンテキストに含める
        let leftSideContext = self.client().string(from: leftRange, actualRange: &actual)
        self.segmentsManager.appendDebugMessage("\(#function): leftSideContext=\(leftSideContext ?? "nil")")
        return leftSideContext
    }
}

extension azooKeyMacInputController: ReplaceSuggestionsViewControllerDelegate {
    @MainActor func replaceSuggestionSelectionChanged(_ row: Int) {
        self.segmentsManager.requestSelectingSuggestionRow(row)
    }

    func replaceSuggestionSubmitted() {
        Task { @MainActor in
            if let candidate = self.replaceSuggestionsViewController.getSelectedCandidate() {
                if let client = self.client() {
                    // 選択された候補をテキストとして挿入
                    client.insertText(candidate.text, replacementRange: NSRange(location: NSNotFound, length: 0))
                    // サジェスト候補ウィンドウを非表示にする
                    self.replaceSuggestionWindow.setIsVisible(false)
                    self.replaceSuggestionWindow.orderOut(nil)
                    // 変換状態をリセット
                    self.segmentsManager.stopComposition()
                }
            }
        }
    }
}

// Suggest Candidate
extension azooKeyMacInputController {
    // MARK: - Window Setup
    func setupReplaceSuggestionWindow() {
        self.replaceSuggestionsViewController = ReplaceSuggestionsViewController()
        self.replaceSuggestionWindow = NSWindow(contentViewController: self.replaceSuggestionsViewController)
        self.replaceSuggestionWindow.styleMask = [.borderless]
        self.replaceSuggestionWindow.level = .popUpMenu

        var rect: NSRect = .zero
        if let client = self.client() {
            client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        }
        rect.size = .init(width: 400, height: 1000)
        self.replaceSuggestionWindow.setFrame(rect, display: true)
        self.replaceSuggestionWindow.setIsVisible(false)
        self.replaceSuggestionWindow.orderOut(nil)

        self.replaceSuggestionsViewController.delegate = self
    }

    // MARK: - Replace Suggestion Request Handling
    @MainActor func requestReplaceSuggestion() {
        self.segmentsManager.appendDebugMessage("requestReplaceSuggestion: 開始")

        // リクエスト開始時に前回の候補をクリアし、ウィンドウを非表示にする
        self.segmentsManager.setReplaceSuggestions([])
        self.replaceSuggestionWindow.setIsVisible(false)
        self.replaceSuggestionWindow.orderOut(nil)

        let composingText = self.segmentsManager.convertTarget

        // プロンプトを取得
        let prompt = self.getLeftSideContext(maxCount: 100) ?? ""

        self.segmentsManager.appendDebugMessage("プロンプト取得成功: \(prompt) << \(composingText)")

        let apiKey = Config.OpenAiApiKey().value
        let modelName = Config.OpenAiModelName().value
        let request = OpenAIRequest(prompt: prompt, target: composingText, modelName: modelName)
        self.segmentsManager.appendDebugMessage("APIリクエスト準備完了: prompt=\(prompt), target=\(composingText), modelName=\(modelName)")
        self.segmentsManager.appendDebugMessage("Using OpenAI Model: \(modelName)")

        // 非同期タスクでリクエストを送信
        Task {
            do {
                self.segmentsManager.appendDebugMessage("APIリクエスト送信中...")
                let predictions = try await OpenAIClient.sendRequest(request, apiKey: apiKey, segmentsManager: segmentsManager)
                self.segmentsManager.appendDebugMessage("APIレスポンス受信成功: \(predictions)")

                // String配列からCandidate配列に変換
                let candidates = predictions.map { text in
                    Candidate(
                        text: text,
                        value: PValue(0),
                        correspondingCount: text.count,
                        lastMid: 0,
                        data: [],
                        actions: [],
                        inputable: true
                    )
                }

                self.segmentsManager.appendDebugMessage("候補変換成功: \(candidates.map { $0.text })")

                // 候補をウィンドウに更新
                await MainActor.run {
                    self.segmentsManager.appendDebugMessage("候補ウィンドウ更新中...")
                    if !candidates.isEmpty {
                        self.segmentsManager.setReplaceSuggestions(candidates)
                        self.replaceSuggestionsViewController.updateCandidates(candidates, selectionIndex: nil, cursorLocation: getCursorLocation())
                        self.replaceSuggestionWindow.setIsVisible(true)
                        self.replaceSuggestionWindow.makeKeyAndOrderFront(nil)
                        self.segmentsManager.appendDebugMessage("候補ウィンドウ更新完了")
                    }
                }
            } catch {
                self.segmentsManager.appendDebugMessage("APIリクエストエラー: \(error.localizedDescription)")
                print("APIリクエストエラー: \(error.localizedDescription)")
            }
        }
        self.segmentsManager.appendDebugMessage("requestReplaceSuggestion: 終了")
    }

    // MARK: - Window Management
    @MainActor func hideReplaceSuggestionCandidateView() {
        self.replaceSuggestionWindow.setIsVisible(false)
        self.replaceSuggestionWindow.orderOut(nil)
    }

    @MainActor func submitSelectedSuggestionCandidate() {
        if let candidate = self.replaceSuggestionsViewController.getSelectedCandidate() {
            if let client = self.client() {
                client.insertText(candidate.text, replacementRange: NSRange(location: NSNotFound, length: 0))
                self.replaceSuggestionWindow.setIsVisible(false)
                self.replaceSuggestionWindow.orderOut(nil)
                self.segmentsManager.stopComposition()
            }
        }
    }

    // MARK: - Helper Methods
    private func retrySuggestionRequestIfNeeded(cursorPosition: CGPoint) {
        if retryCount < maxRetries {
            retryCount += 1
            self.segmentsManager.appendDebugMessage("再試行中... (\(retryCount)回目)")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.requestReplaceSuggestion()
            }
        } else {
            self.segmentsManager.appendDebugMessage("再試行上限に達しました。")
            retryCount = 0
        }
    }

    // MARK: - Selected Text Transform Methods

    @MainActor
    private func showPromptInputWindow() {
        self.segmentsManager.appendDebugMessage("showPromptInputWindow: Starting")

        // Set flag to prevent recursive calls
        self.isPromptWindowVisible = true

        // Get selected text
        guard let client = self.client() else {
            self.segmentsManager.appendDebugMessage("showPromptInputWindow: No client available")
            self.isPromptWindowVisible = false
            return
        }

        let selectedRange = client.selectedRange()
        self.segmentsManager.appendDebugMessage("showPromptInputWindow: Selected range in window: \(selectedRange)")

        guard selectedRange.length > 0 else {
            self.segmentsManager.appendDebugMessage("showPromptInputWindow: No selected text in window")
            return
        }

        var actualRange = NSRange()
        guard let selectedText = client.string(from: selectedRange, actualRange: &actualRange) else {
            self.segmentsManager.appendDebugMessage("showPromptInputWindow: Failed to get selected text")
            return
        }

        self.segmentsManager.appendDebugMessage("showPromptInputWindow: Selected text: '\(selectedText)'")
        self.segmentsManager.appendDebugMessage("showPromptInputWindow: Storing selected range for later use: \(selectedRange)")

        // Store the selected range and current app info for later use
        let storedSelectedRange = selectedRange
        let currentApp = NSWorkspace.shared.frontmostApplication

        // Get cursor position for window placement
        var cursorLocation = NSPoint.zero
        var rect = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        cursorLocation = rect.origin

        self.segmentsManager.appendDebugMessage("showPromptInputWindow: Cursor location: \(cursorLocation)")

        // Show prompt input window with preview functionality
        self.promptInputWindow.showPromptInput(
            at: cursorLocation,
            onPreview: { [weak self] prompt, callback in
                guard let self = self else {
                    return
                }
                self.segmentsManager.appendDebugMessage("showPromptInputWindow: Preview requested for prompt: '\(prompt)'")

                Task {
                    do {
                        let result = try await self.getTransformationPreview(selectedText: selectedText, prompt: prompt)
                        callback(result)
                    } catch {
                        await MainActor.run {
                            self.segmentsManager.appendDebugMessage("showPromptInputWindow: Preview error: \(error)")
                        }
                        callback("Error: \(error.localizedDescription)")
                    }
                }
            },
            onApply: { [weak self] transformedText in
                guard let self = self else {
                    return
                }
                self.segmentsManager.appendDebugMessage("showPromptInputWindow: Applying transformed text: '\(transformedText)'")

                // Close the window first, then restore focus and replace text
                self.promptInputWindow.close()

                // Restore focus to the original app
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let app = currentApp {
                        app.activate(options: [])
                        self.segmentsManager.appendDebugMessage("showPromptInputWindow: Restored focus to original app")
                    }

                    // Replace text after focus is restored
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.replaceSelectedText(with: transformedText, usingRange: storedSelectedRange)
                    }
                }
            },
            completion: { [weak self] prompt in
                self?.segmentsManager.appendDebugMessage("showPromptInputWindow: Window closed with prompt: \(prompt ?? "nil")")
                self?.isPromptWindowVisible = false
            }
        )
    }

    @MainActor
    private func transformSelectedText(selectedText: String, prompt: String) {
        self.segmentsManager.appendDebugMessage("transformSelectedText: Starting with text '\(selectedText)' and prompt '\(prompt)'")

        guard Config.EnableOpenAiApiKey().value else {
            self.segmentsManager.appendDebugMessage("transformSelectedText: OpenAI API is not enabled")
            return
        }

        self.segmentsManager.appendDebugMessage("transformSelectedText: OpenAI API is enabled, starting request")

        Task {
            do {
                // Create custom prompt for text transformation
                let systemPrompt = """
                Transform the given text according to the user's instructions.
                Return only the transformed text without any additional explanation or formatting.

                User instructions: \(prompt)
                Text to transform: \(selectedText)
                """

                await MainActor.run {
                    self.segmentsManager.appendDebugMessage("transformSelectedText: Created system prompt")
                }

                // Get API key from Config
                let apiKey = Config.OpenAiApiKey().value
                guard !apiKey.isEmpty else {
                    await MainActor.run {
                        self.segmentsManager.appendDebugMessage("transformSelectedText: No OpenAI API key configured")
                    }
                    return
                }

                await MainActor.run {
                    self.segmentsManager.appendDebugMessage("transformSelectedText: API key found, making request")
                }

                let modelName = Config.OpenAiModelName().value
                let results = try await self.sendCustomPromptRequest(
                    prompt: systemPrompt,
                    modelName: modelName,
                    apiKey: apiKey
                )

                await MainActor.run {
                    self.segmentsManager.appendDebugMessage("transformSelectedText: API request completed, results: \(results)")
                }

                if let result = results.first {
                    await MainActor.run {
                        self.segmentsManager.appendDebugMessage("transformSelectedText: Result obtained: '\(result)'")
                        // Note: This method lacks the stored range information.
                        // Text replacement should be handled by showPromptInputWindow instead.
                        self.segmentsManager.appendDebugMessage("transformSelectedText: Note - This path should not be used for text replacement")
                    }
                } else {
                    await MainActor.run {
                        self.segmentsManager.appendDebugMessage("transformSelectedText: No results returned from API")
                    }
                }
            } catch {
                await MainActor.run {
                    self.segmentsManager.appendDebugMessage("transformSelectedText: Error occurred: \(error)")
                }
            }
        }
    }

    @MainActor
    private func replaceSelectedText(with newText: String, usingRange storedRange: NSRange) {
        self.segmentsManager.appendDebugMessage("replaceSelectedText: Starting with new text: '\(newText)'")
        self.segmentsManager.appendDebugMessage("replaceSelectedText: Using stored range: \(storedRange)")

        guard let client = self.client() else {
            self.segmentsManager.appendDebugMessage("replaceSelectedText: No client available")
            return
        }

        // Check current selection for comparison
        let currentSelectedRange = client.selectedRange()
        self.segmentsManager.appendDebugMessage("replaceSelectedText: Current selected range: \(currentSelectedRange)")
        self.segmentsManager.appendDebugMessage("replaceSelectedText: Stored range to use: \(storedRange)")

        if storedRange.length > 0 {
            self.segmentsManager.appendDebugMessage("replaceSelectedText: Starting system-level text replacement")

            // Method 1: Try system-level clipboard replacement (works better with web apps)
            self.replaceTextUsingSystemClipboard(newText: newText, storedRange: storedRange)

        } else {
            self.segmentsManager.appendDebugMessage("replaceSelectedText: Stored range has no length")
        }
    }

    @MainActor
    private func replaceTextUsingSystemClipboard(newText: String, storedRange: NSRange) {
        self.segmentsManager.appendDebugMessage("replaceTextUsingSystemClipboard: Starting clipboard-based replacement")

        // Store the current clipboard content
        let pasteboard = NSPasteboard.general
        let originalClipboardContent = pasteboard.string(forType: .string)
        self.segmentsManager.appendDebugMessage("replaceTextUsingSystemClipboard: Backed up clipboard content")

        // Put the new text in clipboard
        pasteboard.clearContents()
        pasteboard.setString(newText, forType: .string)
        self.segmentsManager.appendDebugMessage("replaceTextUsingSystemClipboard: Set new text to clipboard")

        // First, select the text using the stored range
        guard let client = self.client() else {
            self.segmentsManager.appendDebugMessage("replaceTextUsingSystemClipboard: No client available")
            return
        }

        // Approach: First reselect the text, then use system paste to replace
        self.segmentsManager.appendDebugMessage("replaceTextUsingSystemClipboard: Reselecting text and using system paste")

        // Step 1: Reselect the text using the stored range by simulating mouse selection
        self.reselectTextAndReplace(storedRange: storedRange, newText: newText)

        // Restore clipboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let originalContent = originalClipboardContent {
                pasteboard.clearContents()
                pasteboard.setString(originalContent, forType: .string)
                self.segmentsManager.appendDebugMessage("replaceTextUsingSystemClipboard: Restored clipboard content")
            }
        }
    }

    @MainActor
    private func reselectTextAndReplace(storedRange: NSRange, newText: String) {
        self.segmentsManager.appendDebugMessage("reselectTextAndReplace: Starting with range: \(storedRange)")

        guard let client = self.client() else {
            self.segmentsManager.appendDebugMessage("reselectTextAndReplace: No client available")
            return
        }

        // Method 1: Try to set the selection using IMK
        self.segmentsManager.appendDebugMessage("reselectTextAndReplace: Setting selection using IMK")
        client.setMarkedText("", selectionRange: storedRange, replacementRange: storedRange)

        // Small delay to ensure selection is set
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.segmentsManager.appendDebugMessage("reselectTextAndReplace: Selection should be set, now pasting")

            // Use system paste to replace the selected text
            self.simulateSystemPaste()

            // Verify success and only fallback if needed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let currentRange = client.selectedRange()
                let expectedLocation = storedRange.location + newText.count

                // Only use fallback if the paste didn't work (cursor not at expected location)
                if abs(currentRange.location - expectedLocation) > 5 {
                    self.segmentsManager.appendDebugMessage("reselectTextAndReplace: System paste may have failed, trying IMK fallback")
                    client.insertText(newText, replacementRange: storedRange)
                } else {
                    self.segmentsManager.appendDebugMessage("reselectTextAndReplace: System paste appears successful")
                }
            }
        }
    }

    @MainActor
    private func simulateSystemPaste() {
        self.segmentsManager.appendDebugMessage("simulateSystemPaste: Starting system paste simulation")

        // Create CGEvent source for system events
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            self.segmentsManager.appendDebugMessage("simulateSystemPaste: Failed to create event source")
            return
        }

        // Simulate Cmd+V to paste
        if let cmdVDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x09, keyDown: true),
           let cmdVUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x09, keyDown: false) {

            cmdVDown.flags = .maskCommand
            cmdVUp.flags = .maskCommand

            self.segmentsManager.appendDebugMessage("simulateSystemPaste: Simulating Cmd+V")
            cmdVDown.post(tap: .cghidEventTap)
            cmdVUp.post(tap: .cghidEventTap)

            self.segmentsManager.appendDebugMessage("simulateSystemPaste: Paste completed")
        }
    }

    @MainActor
    private func simulateSystemReplacement(storedRange: NSRange) {
        self.segmentsManager.appendDebugMessage("simulateSystemReplacement: Starting system event simulation")

        // Try to reselect the text using accessibility and then replace with paste
        self.attemptTextReselectionAndReplace(storedRange: storedRange)
    }

    @MainActor
    private func attemptTextReselectionAndReplace(storedRange: NSRange) {
        self.segmentsManager.appendDebugMessage("attemptTextReselectionAndReplace: Attempting to reselect and replace text")

        guard let client = self.client() else {
            self.segmentsManager.appendDebugMessage("attemptTextReselectionAndReplace: No client available")
            return
        }

        // Try different methods to replace text

        // Method 1: Force selection and then use paste
        self.segmentsManager.appendDebugMessage("attemptTextReselectionAndReplace: Method 1 - Force selection then paste")

        // Set selection to the stored range
        client.setMarkedText("", selectionRange: storedRange, replacementRange: storedRange)

        // Small delay to ensure selection is set
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            // Create CGEvent source for system events
            guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
                self.segmentsManager.appendDebugMessage("attemptTextReselectionAndReplace: Failed to create event source")
                return
            }

            // Simulate Cmd+V to paste the new text
            if let cmdVDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x09, keyDown: true),
               let cmdVUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x09, keyDown: false) {

                cmdVDown.flags = .maskCommand
                cmdVUp.flags = .maskCommand

                self.segmentsManager.appendDebugMessage("attemptTextReselectionAndReplace: Simulating Cmd+V paste")
                cmdVDown.post(tap: .cghidEventTap)
                cmdVUp.post(tap: .cghidEventTap)

                self.segmentsManager.appendDebugMessage("attemptTextReselectionAndReplace: Paste command sent")
            }
        }
    }

    // Custom prompt request for text transformation
    private func sendCustomPromptRequest(prompt: String, modelName: String, apiKey: String) async throws -> [String] {
        await MainActor.run {
            self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: Starting API request to OpenAI")
        }

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            await MainActor.run {
                self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: Invalid URL")
            }
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that transforms text according to user instructions."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 150,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        await MainActor.run {
            self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: Sending request to OpenAI API")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        await MainActor.run {
            self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: Received response from API")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            await MainActor.run {
                self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: No HTTP response")
            }
            throw OpenAIError.noServerResponse
        }

        await MainActor.run {
            self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: HTTP status code: \(httpResponse.statusCode)")
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(bytes: data, encoding: .utf8) ?? "Body is not encoded in UTF-8"
            await MainActor.run {
                self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: API error - Status: \(httpResponse.statusCode), Body: \(responseBody)")
            }
            throw OpenAIError.invalidResponseStatus(code: httpResponse.statusCode, body: responseBody)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let jsonDict = jsonObject as? [String: Any],
              let choices = jsonDict["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            await MainActor.run {
                self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: Failed to parse API response structure")
            }
            throw OpenAIError.invalidResponseStructure(jsonObject)
        }

        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run {
            self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: Successfully parsed result: '\(result)'")
        }

        return [result]
    }

    // Get transformation preview without applying it
    private func getTransformationPreview(selectedText: String, prompt: String) async throws -> String {
        await MainActor.run {
            self.segmentsManager.appendDebugMessage("getTransformationPreview: Starting preview request")
        }

        guard Config.EnableOpenAiApiKey().value else {
            await MainActor.run {
                self.segmentsManager.appendDebugMessage("getTransformationPreview: OpenAI API is not enabled")
            }
            throw NSError(domain: "TransformationError", code: -1, userInfo: [NSLocalizedDescriptionKey: "OpenAI API is not enabled"])
        }

        // Create custom prompt for text transformation
        let systemPrompt = """
        Transform the given text according to the user's instructions.
        Return only the transformed text without any additional explanation or formatting.

        User instructions: \(prompt)
        Text to transform: \(selectedText)
        """

        // Get API key from Config
        let apiKey = Config.OpenAiApiKey().value
        guard !apiKey.isEmpty else {
            await MainActor.run {
                self.segmentsManager.appendDebugMessage("getTransformationPreview: No OpenAI API key configured")
            }
            throw NSError(domain: "TransformationError", code: -2, userInfo: [NSLocalizedDescriptionKey: "No OpenAI API key configured"])
        }

        await MainActor.run {
            self.segmentsManager.appendDebugMessage("getTransformationPreview: Sending preview request to API")
        }

        let modelName = Config.OpenAiModelName().value
        let results = try await self.sendCustomPromptRequest(
            prompt: systemPrompt,
            modelName: modelName,
            apiKey: apiKey
        )

        guard let result = results.first else {
            await MainActor.run {
                self.segmentsManager.appendDebugMessage("getTransformationPreview: No results returned from API")
            }
            throw NSError(domain: "TransformationError", code: -3, userInfo: [NSLocalizedDescriptionKey: "No results returned from API"])
        }

        await MainActor.run {
            self.segmentsManager.appendDebugMessage("getTransformationPreview: Preview result: '\(result)'")
        }

        return result
    }
}
