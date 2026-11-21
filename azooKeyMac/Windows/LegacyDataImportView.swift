import Cocoa
import Core
import SwiftUI

@MainActor
struct LegacyDataImportView: View {
    let privateApplicationSupportURL: URL

    @State private var showingResult = false
    @State private var result = ""

    var body: some View {
        LabeledContent("旧データ") {
            Menu("読み込む") {
                Button("アプリ専用領域から読み込む") {
                    self.importData(from: self.privateApplicationSupportURL.appendingPathComponent("memory", isDirectory: true)) {
                        try UserDefaults.standard.data(forKey: Config.UserDictionary.key).map {
                            try JSONDecoder().decode(Config.UserDictionary.Value.self, from: $0)
                        }
                    }
                }
                Button("旧App Groupフォルダを選択…") {
                    self.selectLegacyGroupFolder()
                }
                Button("履歴学習フォルダを選択…") {
                    self.selectFolder(
                        title: "履歴学習フォルダを選択",
                        message: "memory フォルダ、または置き換え時に作成された memory-backup フォルダを選択してください。",
                        directory: AppGroup.applicationSupportDirectoryURL()
                    ) { folder in
                        self.importData(from: folder)
                    }
                }
            }
        }
        .alert("旧データの読み込み", isPresented: $showingResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(self.result)
        }
    }

    private func selectLegacyGroupFolder() {
        let group = LegacyDataMigration.appGroupIdentifier
        let home = NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory()
        self.selectFolder(
            title: "旧App Groupフォルダを選択",
            message: "\(group) フォルダ、またはFinderでコピーした同フォルダを選択してください。",
            directory: URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent("Library/Group Containers", isDirectory: true)
        ) { folder in
            let library = folder.appendingPathComponent("Library", isDirectory: true)
            self.importData(from: library.appendingPathComponent("Application Support/azooKey/memory", isDirectory: true)) {
                try LegacyDataMigration.readUserDictionary(from: library.appendingPathComponent("Preferences/\(group).plist"))
            }
        }
    }

    private func selectFolder(title: String, message: String, directory: URL, importFolder: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.directoryURL = directory
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let folder = panel.url else {
            return
        }

        let hasAccess = folder.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                folder.stopAccessingSecurityScopedResource()
            }
        }
        importFolder(folder)
    }

    private func importData(
        from memoryDirectory: URL,
        readDictionary: () throws -> Config.UserDictionary.Value? = { nil }
    ) {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            return
        }
        var messages: [String] = []
        do {
            if let legacy = try readDictionary() {
                let dictionary = Config.UserDictionary()
                let current = dictionary.value
                let merged = LegacyDataMigration.mergeUserDictionary(legacy, into: current)
                let added = merged.items.count - current.items.count
                if added > 0 {
                    dictionary.value = merged
                    messages.append("ユーザ辞書に\(added)件を追加しました。")
                } else {
                    messages.append("ユーザ辞書に追加できる単語はありませんでした。")
                }
                appDelegate.exportUserDictionaryAndReloadConverter()
            }
        } catch {
            messages.append("ユーザ辞書を読み込めませんでした。\(error.localizedDescription)")
        }

        appDelegate.kanaKanjiConverter.commitUpdateLearningData()
        do {
            let destination = AppGroup.memoryDirectoryURL()
            var learning = try LegacyDataMigration.stageLearning(from: memoryDirectory, for: destination)
            if learning == .keptCurrent && self.confirmLearningReplacement() {
                learning = try LegacyDataMigration.stageLearning(from: memoryDirectory, for: destination, replacingCurrent: true)
            }
            switch learning {
            case .missing:
                break
            case .keptCurrent:
                messages.append("新しい保存先に履歴学習データがあるため、現在の学習を保持しました。")
            case .staged:
                messages.append("履歴学習データを読み込むにはIMEを再起動してください。")
            }
        } catch {
            messages.append("履歴学習データを読み込めませんでした。\(error.localizedDescription)")
        }
        self.result = messages.isEmpty ? "読み込めるユーザ辞書や履歴学習データが見つかりませんでした。" : messages.joined(separator: "\n")
        self.showingResult = true
    }

    private func confirmLearningReplacement() -> Bool {
        let alert = NSAlert()
        alert.messageText = "履歴学習データを旧データに置き換えますか？"
        alert.informativeText = "現在の学習データは、アプリデータ内の memory-backup フォルダにバックアップします。"
        alert.addButton(withTitle: "バックアップして置き換える")
        alert.addButton(withTitle: "現在の学習を保持する")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
