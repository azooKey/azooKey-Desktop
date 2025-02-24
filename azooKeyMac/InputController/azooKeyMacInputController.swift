//
//  azooKeyMacInputController.swift
//  azooKeyMacInputController
//
//  Created by ensan on 2021/09/07.
//

import Cocoa
import InputMethodKit
import KanaKanjiConverterModuleWithDefaultDictionary

@objc(azooKeyMacInputController)
class azooKeyMacInputController: IMKInputController { // swiftlint:disable:this type_name
    var segmentsManager: SegmentsManager
    private var inputState: InputState = .none
    var zenzaiEnabled: Bool {
        Config.ZenzaiIntegration().value
    }
    var liveConversionEnabled: Bool {
        Config.LiveConversion().value
    }
    var englishConversionEnabled: Bool {
        Config.EnglishConversion().value
    }

    var appMenu: NSMenu
    var zenzaiToggleMenuItem: NSMenuItem
    var liveConversionToggleMenuItem: NSMenuItem
    var englishConversionToggleMenuItem: NSMenuItem

    private var candidatesWindow: NSWindow
    private var candidatesViewController: CandidatesViewController

    private var replaceSuggestionWindow: NSWindow
    private var replaceSuggestionsViewController: ReplaceSuggestionsViewController

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        self.segmentsManager = SegmentsManager()

        self.appMenu = NSMenu(title: "azooKey")
        self.zenzaiToggleMenuItem = NSMenuItem()
        self.liveConversionToggleMenuItem = NSMenuItem()
        self.englishConversionToggleMenuItem = NSMenuItem()

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
        self.updateEnglishConversionToggleMenuItem(newValue: self.englishConversionEnabled)
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
            let directMode = value == "com.apple.inputmethod.Roman"
            // 英数/かなの対応するキーが推された場合と同等のイベントを発生させる
            let userAction: UserAction? = if directMode, self.inputState != .english {
                .英数
            } else if !directMode, self.inputState == .english {
                .かな
            } else {
                nil
            }
            if let userAction {
                let (clientAction, clientActionCallback) = self.inputState.event(
                    eventCore: .init(modifierFlags: []),
                    userAction: userAction,
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

        let userAction = switch self.inputState {
        case .english:
            InputMode.getUserActionInEnglishMode(event: event)
        case .none, .composing, .previewing, .selecting, .replaceSuggestion:
            InputMode.getUserAction(event: event)
        }
        let (clientAction, clientActionCallback) = inputState.event(
            event,
            userAction: userAction,
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
            self.candidatesViewController.selectNumberCandidate(num: num)
            self.submitSelectedCandidate()
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
            if inputState == .english && self.inputState != .english {
                // 日本語→英語の遷移の場合
                self.switchInputMode(mode: .roman, client: client)
            } else if inputState != .english && self.inputState == .english {
                // 英語→日本語の遷移の場合
                self.switchInputMode(mode: .japanese, client: client)
            }
            self.inputState = inputState
        case .basedOnBackspace(let ifIsEmpty, let ifIsNotEmpty), .basedOnSubmitCandidate(let ifIsEmpty, let ifIsNotEmpty):
            self.inputState = self.segmentsManager.isEmpty ? ifIsEmpty : ifIsNotEmpty
        }

        self.refreshMarkedText()
        self.refreshCandidateWindow()
        return true
    }

    @MainActor func switchInputMode(mode: ClientAction.InputMode, client: IMKTextInput) {
        client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.US")
        switch mode {
        case .roman:
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
        let request = OpenAIRequest(prompt: prompt, target: composingText)
        self.segmentsManager.appendDebugMessage("APIリクエスト準備完了: prompt=\(prompt), target=\(composingText)")

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
}
