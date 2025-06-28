import Cocoa
import InputMethodKit

extension azooKeyMacInputController {
    // MARK: - Settings and Menu Items

    func setupMenu() {
        self.zenzaiToggleMenuItem = NSMenuItem(title: "Zenzai（ニューラルかな漢字変換）", action: #selector(self.toggleZenzai(_:)), keyEquivalent: "")
        self.liveConversionToggleMenuItem = NSMenuItem(title: "ライブ変換", action: #selector(self.toggleLiveConversion(_:)), keyEquivalent: "")
        self.appMenu.addItem(self.zenzaiToggleMenuItem)
        self.appMenu.addItem(self.liveConversionToggleMenuItem)
        self.appMenu.addItem(NSMenuItem.separator())
        let callXPCMenuItem = NSMenuItem(title: "Converter Processと通信", action: #selector(self.callConverterProcess(_:)), keyEquivalent: "")
        self.appMenu.addItem(callXPCMenuItem)
        self.appMenu.addItem(NSMenuItem(title: "詳細設定を開く", action: #selector(self.openConfigWindow(_:)), keyEquivalent: ""))
        self.appMenu.addItem(NSMenuItem(title: "View on GitHub", action: #selector(self.openGitHubRepository(_:)), keyEquivalent: ""))
    }

    @objc private func toggleZenzai(_ sender: Any) {
        self.segmentsManager.appendDebugMessage("\(#line): toggleZenzai")
        let config = Config.ZenzaiIntegration()
        config.value = !self.zenzaiEnabled
        self.updateZenzaiToggleMenuItem(newValue: config.value)
    }

    func updateZenzaiToggleMenuItem(newValue: Bool) {
        self.zenzaiToggleMenuItem.state = newValue ? .on : .off
        self.zenzaiToggleMenuItem.title = "Zenzai（ニューラルかな漢字変換）"
    }

    @objc func toggleLiveConversion(_ sender: Any) {
        self.segmentsManager.appendDebugMessage("\(#line): toggleLiveConversion")
        let config = Config.LiveConversion()
        config.value = !self.liveConversionEnabled
        self.updateLiveConversionToggleMenuItem(newValue: config.value)
    }

    func updateLiveConversionToggleMenuItem(newValue: Bool) {
        self.liveConversionToggleMenuItem.state = newValue ? .on : .off
        self.liveConversionToggleMenuItem.title = "ライブ変換"
    }

    @objc func openGitHubRepository(_ sender: Any) {
        guard let url = URL(string: "https://github.com/ensan-hcl/azooKey-Desktop") else {
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
        } catch {
            self.segmentsManager.appendDebugMessage("\(#line): \(error.localizedDescription)")
        }
    }

    @objc func callConverterProcess(_ sender: Any) {
        self.callXPCExample(firstNumber: 42, secondNumber: 58) { result in
            if let result = result {
                self.segmentsManager.appendDebugMessage("XPC result: \(result)")
            } else {
                self.segmentsManager.appendDebugMessage("XPC call failed")
            }
        }
    }
}
