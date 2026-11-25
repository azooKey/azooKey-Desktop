import Cocoa
import Core
import InputMethodKit

extension azooKeyMacInputController {
    // MARK: - Settings and Menu Items

    func setupMenu() {
        self.appMenu.autoenablesItems = true
        self.liveConversionToggleMenuItem = NSMenuItem(title: "ライブ変換", action: #selector(self.toggleLiveConversion(_:)), keyEquivalent: "")
        self.appMenu.addItem(self.liveConversionToggleMenuItem)
        self.transformSelectedTextMenuItem = NSMenuItem(title: TransformMenuTitle.normal, action: #selector(self.performTransformSelectedText(_:)), keyEquivalent: "")
        self.updateTransformSelectedTextMenuItemShortcut()
        self.transformSelectedTextMenuItem.target = self
        self.appMenu.addItem(self.transformSelectedTextMenuItem)
        self.appMenu.addItem(NSMenuItem.separator())
        self.appMenu.addItem(NSMenuItem(title: "設定…", action: #selector(self.openConfigWindow(_:)), keyEquivalent: ""))
        self.appMenu.addItem(NSMenuItem(title: "View on GitHub…", action: #selector(self.openGitHubRepository(_:)), keyEquivalent: ""))
        self.updateTransformSelectedTextMenuItemTitle()
    }

    func updateTransformSelectedTextMenuItemShortcut() {
        let shortcut = Config.TransformShortcut().value
        var mask: NSEvent.ModifierFlags = []
        if shortcut.modifiers.contains(.control) { mask.insert(.control) }
        if shortcut.modifiers.contains(.option) { mask.insert(.option) }
        if shortcut.modifiers.contains(.shift) { mask.insert(.shift) }
        if shortcut.modifiers.contains(.command) { mask.insert(.command) }
        self.transformSelectedTextMenuItem.keyEquivalent = shortcut.key
        self.transformSelectedTextMenuItem.keyEquivalentModifierMask = mask
    }

    @objc func toggleLiveConversion(_ sender: Any) {
        self.appendDebugMessage("\(#line): toggleLiveConversion")
        let config = Config.LiveConversion()
        config.value = !self.liveConversionEnabled
        self.updateLiveConversionToggleMenuItem(newValue: config.value)
    }

    func updateLiveConversionToggleMenuItem(newValue: Bool) {
        self.liveConversionToggleMenuItem.state = newValue ? .on : .off
        self.liveConversionToggleMenuItem.title = "ライブ変換"
    }

    private enum TransformMenuTitle {
        static let normal = "いい感じ変換"
        static let noBackend = "いい感じ変換（無効/バックエンドなし）"
    }

    @MainActor @objc func performTransformSelectedText(_ sender: Any) {
        let aiBackendEnabled = Config.AIBackendPreference().value != .off
        self.updateTransformSelectedTextMenuItemTitle(aiBackendEnabled: aiBackendEnabled)
        guard aiBackendEnabled else {
            return
        }
        guard !self.isPromptWindowVisible else {
            return
        }
        guard let client = self.client() else {
            return
        }
        let hasSelection = client.selectedRange().length > 0
        if hasSelection {
            _ = self.handleClientAction(.showPromptInputWindow, clientActionCallback: .fallthrough, client: client)
            return
        }
        switch self.inputState {
        case .composing, .replaceSuggestion:
            _ = self.handleClientAction(.requestReplaceSuggestion, clientActionCallback: .transition(.replaceSuggestion), client: client)
        default:
            break
        }
    }

    @MainActor @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem == self.transformSelectedTextMenuItem else {
            return true
        }
        self.updateTransformSelectedTextMenuItemTitle()
        guard !self.isPromptWindowVisible else {
            return false
        }
        guard let client = self.client() else {
            return false
        }
        // 選択範囲はメニューの検証時に取得し、入力開始時の同期問い合わせを避ける。
        return self.inputState == .composing
            || self.inputState == .replaceSuggestion
            || client.selectedRange().length > 0
    }

    func updateTransformSelectedTextMenuItemTitle(aiBackendEnabled: Bool = Config.AIBackendPreference().value != .off) {
        self.transformSelectedTextMenuItem.title = aiBackendEnabled ? TransformMenuTitle.normal : TransformMenuTitle.noBackend
    }

    @objc func openGitHubRepository(_ sender: Any) {
        guard let url = URL(string: "https://github.com/azooKey/azooKey-Desktop") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc func openConfigWindow(_ sender: Any) {
        (NSApplication.shared.delegate as? AppDelegate)!.openConfigWindow()
    }

    // MARK: - Application Support Directory
    func prepareApplicationSupportDirectory() {
        do {
            self.segmentsManager.appendDebugMessage("\(#line): Applicatiion Support Directory Path: \(self.segmentsManager.azooKeyMemoryDir)")
            try FileManager.default.createDirectory(at: self.segmentsManager.azooKeyMemoryDir, withIntermediateDirectories: true)
            self.segmentsManager.appendDebugMessage("\(#line): Debug TypoCorrection Download Directory Path: \(self.segmentsManager.downloadedInputN5LMDir)")
            try FileManager.default.createDirectory(at: self.segmentsManager.downloadedInputN5LMDir, withIntermediateDirectories: true)
        } catch {
            self.segmentsManager.appendDebugMessage("\(#line): \(error.localizedDescription)")
        }
    }
}
