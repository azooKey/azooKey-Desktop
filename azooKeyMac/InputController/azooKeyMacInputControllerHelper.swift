import Cocoa
import InputMethodKit

extension azooKeyMacInputController {
    // MARK: - Settings and Menu Items

    func setupMenu() {
        self.liveConversionToggleMenuItem = NSMenuItem(title: "ライブ変換", action: #selector(self.toggleLiveConversion(_:)), keyEquivalent: "")
        self.appMenu.addItem(self.liveConversionToggleMenuItem)
        self.appMenu.addItem(NSMenuItem.separator())
        self.appMenu.addItem(NSMenuItem(title: "設定…", action: #selector(self.openConfigWindow(_:)), keyEquivalent: ""))
        self.appMenu.addItem(NSMenuItem(title: "View on GitHub…", action: #selector(self.openGitHubRepository(_:)), keyEquivalent: ""))
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
        } catch {
            self.segmentsManager.appendDebugMessage("\(#line): \(error.localizedDescription)")
        }
    }
}
