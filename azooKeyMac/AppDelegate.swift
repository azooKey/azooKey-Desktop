//
//  AppDelegate.swift
//  AppDelegate
//
//  Created by ensan on 2021/09/06.
//

import Cocoa
import Core
import InputMethodKit
import KanaKanjiConverterModuleWithDefaultDictionary
import Sparkle
import SwiftUI

// Necessary to launch this app
class NSManualApplication: NSApplication {
    let appDelegate = AppDelegate()

    override init() {
        super.init()
        self.delegate = appDelegate
    }

    required init?(coder: NSCoder) {
        // No need for implementation
        fatalError("init(coder:) has not been implemented")
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var server = IMKServer()
    weak var configWindow: NSWindow?
    weak var userDictionaryEditorWindow: NSWindow?
    var configWindowController: NSWindowController?
    var userDictionaryEditorWindowController: NSWindowController?
    var kanaKanjiConverter = KanaKanjiConverter.withDefaultDictionary()
    private var updaterController: SPUStandardUpdaterController?

    private var userDictionaryMemoryDirectoryURL: URL {
        AppGroup.memoryDirectoryURL()
    }

    private func exportInitialUserDictionaryIfNeeded() {
        let memoryDirectoryURL = self.userDictionaryMemoryDirectoryURL
        Task.detached(priority: .utility) {
            guard !CompiledUserDictionaryStore.hasExportedDictionary(memoryDirectoryURL: memoryDirectoryURL) else {
                return
            }
            do {
                try CompiledUserDictionaryStore.exportCurrentDictionaries(memoryDirectoryURL: memoryDirectoryURL)
                await MainActor.run {
                    self.reloadUserDictionary(memoryDirectoryURL: memoryDirectoryURL)
                }
            } catch {
                print("Failed to export compiled user dictionary: \(error)")
            }
        }
    }

    func exportUserDictionaryAndReloadConverter() {
        let memoryDirectoryURL = self.userDictionaryMemoryDirectoryURL
        Task.detached(priority: .utility) {
            do {
                try CompiledUserDictionaryStore.exportCurrentDictionaries(memoryDirectoryURL: memoryDirectoryURL)
                await MainActor.run {
                    self.reloadUserDictionary(memoryDirectoryURL: memoryDirectoryURL)
                }
            } catch {
                print("Failed to export compiled user dictionary: \(error)")
            }
        }
    }

    private func reloadUserDictionary(memoryDirectoryURL: URL) {
        self.kanaKanjiConverter.updateUserDictionaryURL(
            CompiledUserDictionaryStore.directoryURL(memoryDirectoryURL: memoryDirectoryURL),
            forceReload: true
        )
    }

    private static func buildSwiftUIWindow(
        _ view: some View,
        contentRect: NSRect = NSRect(x: 0, y: 0, width: 400, height: 300),
        styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .borderless],
        title: String = ""
    ) -> (window: NSWindow, windowController: NSWindowController) {
        // Create a new window
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        // Set the window title
        window.title = title
        window.contentViewController = NSHostingController(rootView: view)
        // Keep window with in a controller
        let windowController = NSWindowController(window: window)
        // Show the window
        window.level = .modalPanel
        window.makeKeyAndOrderFront(nil)
        return (window, windowController)
    }

    func openConfigWindow() {
        if let configWindow {
            // Show the window
            configWindow.level = .modalPanel
            configWindow.makeKeyAndOrderFront(nil)
        } else {
            // Create a new window
            (self.configWindow, self.configWindowController) = Self.buildSwiftUIWindow(ConfigWindow(), title: "設定")
        }
    }

    func openUserDictionaryEditorWindow() {
        if let userDictionaryEditorWindow {
            // Show the window
            userDictionaryEditorWindow.level = .modalPanel
            userDictionaryEditorWindow.makeKeyAndOrderFront(nil)
        } else {
            (self.userDictionaryEditorWindow, self.userDictionaryEditorWindowController) = Self.buildSwiftUIWindow(UserDictionaryEditorWindow(), title: "設定")
        }
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        guard let updaterController else {
            let alert = NSAlert()
            alert.messageText = "自動アップデートは未設定です"
            alert.informativeText = "SPARKLE_FEED_URL と SPARKLE_PUBLIC_ED_KEY を設定したビルドで利用できます。"
            alert.runModal()
            return
        }
        updaterController.checkForUpdates(sender)
    }

    private func configureUpdaterIfAvailable() {
        guard
            let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            !feedURL.isEmpty,
            let publicEDKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            !publicEDKey.isEmpty
        else {
            NSLog("Sparkle updater is disabled because SUFeedURL or SUPublicEDKey is not configured.")
            return
        }
        self.updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    private func addApplicationMenuIfNeeded() {
        let appMenuItem = NSMenuItem(title: "azooKey", action: nil, keyEquivalent: "")
        NSApp.mainMenu?.addItem(appMenuItem)

        let appSubmenu = NSMenu(title: "azooKey")
        appMenuItem.submenu = appSubmenu

        let checkForUpdatesItem = NSMenuItem(title: "更新を確認...", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        checkForUpdatesItem.target = self
        appSubmenu.addItem(checkForUpdatesItem)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Insert code here to initialize your application
        self.server = IMKServer(name: Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String, bundleIdentifier: Bundle.main.bundleIdentifier)
        NSLog("tried connection")
        self.configureUpdaterIfAvailable()

        // Keychainから設定値を非同期で読み込み
        Task {
            await Config.OpenAiApiKey.loadFromKeychain()
        }
        self.exportInitialUserDictionaryIfNeeded()

        // Check if mainMenu exists, or create it
        if NSApp.mainMenu == nil {
            NSApp.mainMenu = NSMenu()
        }

        self.addApplicationMenuIfNeeded()

        // Add an Edit menu
        let editMenu = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        NSApp.mainMenu?.addItem(editMenu)
        let editSubmenu = NSMenu(title: "Edit")
        editMenu.submenu = editSubmenu

        // Add standard Edit actions
        editSubmenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editSubmenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editSubmenu.addItem(NSMenuItem.separator())
        editSubmenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editSubmenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editSubmenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editSubmenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Insert code here to tear down your application
    }
}
