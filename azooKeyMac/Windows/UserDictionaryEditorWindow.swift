//
//  UserDictionaryEditorWindow.swift
//  azooKeyMac
//
//  Created by miwa on 2024/09/22.
//

import AppKit
import Core
import SwiftUI
import UniformTypeIdentifiers

struct UserDictionaryEditorWindow: View {

    @ConfigState private var userDictionary = Config.UserDictionary()

    @State private var editTargetID: UUID?
    @State private var undoItem: Config.UserDictionaryEntry?
    @State private var importFormat: UserDictionaryTextFormat = .automatic
    @State private var alertMessage = ""
    @State private var showingAlert = false

    @ViewBuilder
    private func helpButton(helpContent: LocalizedStringKey, isPresented: Binding<Bool>) -> some View {
        if #available(macOS 14, *) {
            Button("ヘルプ", systemImage: "questionmark") {
                isPresented.wrappedValue = true
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .popover(isPresented: isPresented) {
                Text(helpContent).padding()
            }
        }
    }

    /// Read the current user dictionary value through the `@ConfigState` binding (i.e. the
    /// in-memory store) instead of `userDictionary.value` (which decodes from UserDefaults
    /// on every access). Writes still go through `updateUserDictionary` below.
    private var userDictionaryValue: Config.UserDictionary.Value {
        self.$userDictionary.wrappedValue
    }

    private var isAdditionDisabled: Bool {
        self.userDictionaryValue.items.count >= 50
    }

    /// Mutate the user dictionary through the `@ConfigState` binding so the backing store and
    /// any other window observing the same item are kept in sync. Direct `userDictionary.value`
    /// mutation only writes to UserDefaults and bypasses the store, which left "x件のアイテム"
    /// counts stale in other views (see fix/user-dictionary-count-update).
    private func updateUserDictionary(_ transform: (inout Config.UserDictionary.Value) -> Void) {
        var value = self.$userDictionary.wrappedValue
        transform(&value)
        self.$userDictionary.wrappedValue = value
    }

    var body: some View {
        VStack {
            Text("ユーザ辞書の設定")
                .bold()
                .font(.title)
            Text("この機能はβ版です。予告なく仕様を変更することがあります。")
                .font(.caption)
            importExportControls
            Spacer()
            if let editTargetID {
                let itemBinding = Binding(
                    get: {
                        self.userDictionaryValue.items.first {
                            $0.id == editTargetID
                        } ?? .init(word: "", reading: "")
                    },
                    set: { newItem in
                        self.updateUserDictionary { value in
                            if let index = value.items.firstIndex(where: { $0.id == editTargetID }) {
                                value.items[index] = newItem
                            }
                        }
                    }
                )
                Form {
                    TextField("単語", text: itemBinding.word)
                    TextField("読み", text: itemBinding.reading)
                    TextField("ヒント", text: itemBinding.nonNullHint)
                    HStack {
                        Spacer()
                        Button("完了", systemImage: "checkmark") {
                            self.editTargetID = nil
                        }
                        Spacer()
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Button("追加", systemImage: "plus") {
                        let newItem = Config.UserDictionaryEntry(word: "", reading: "", hint: nil)
                        self.updateUserDictionary { value in
                            value.items.append(newItem)
                        }
                        self.editTargetID = newItem.id
                        self.undoItem = nil
                    }
                    .disabled(self.isAdditionDisabled)
                    if self.isAdditionDisabled {
                        Label("50件を超えています", systemImage: "exclamationmark.octagon")
                            .foregroundStyle(.red)
                    }
                    if let undoItem {
                        Button("元に戻す", systemImage: "arrow.uturn.backward") {
                            self.updateUserDictionary { value in
                                value.items.append(undoItem)
                            }
                            self.undoItem = nil
                        }
                    }
                    Spacer()
                }
            }
            HStack {
                Spacer()
                Table(self.userDictionaryValue.items) {
                    TableColumn("") { item in
                        HStack {
                            Button("編集する", systemImage: "pencil") {
                                self.editTargetID = item.id
                                self.undoItem = nil
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                            Button("削除する", systemImage: "trash", role: .destructive) {
                                self.updateUserDictionary { value in
                                    if let itemIndex = value.items.firstIndex(where: { $0.id == item.id }) {
                                        self.undoItem = value.items[itemIndex]
                                        value.items.remove(at: itemIndex)
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                        }
                    }
                    TableColumn("単語", value: \.word)
                    TableColumn("読み", value: \.reading)
                    TableColumn("ヒント", value: \.nonNullHint)
                }
                .disabled(editTargetID != nil)
                Spacer()
            }
            Spacer()
        }
        .frame(minHeight: 300, maxHeight: 600)
        .frame(minWidth: 600, maxWidth: 800)
        .alert("ユーザ辞書", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private var importExportControls: some View {
        HStack(spacing: 8) {
            Picker("形式", selection: $importFormat) {
                ForEach(UserDictionaryTextFormat.allCases) { format in
                    Text(format.localizedName).tag(format)
                }
            }
            .frame(width: 220)

            Button("読み込む", systemImage: "square.and.arrow.down") {
                importFromFile()
            }
            Button("書き出す", systemImage: "square.and.arrow.up") {
                exportToFile()
            }
        }
        .controlSize(.regular)
    }

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "ユーザ辞書ファイルを選択"

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(contentsOf: url)
                guard let text = UserDictionaryTextCodec.decodeText(from: data) else {
                    showAlert("ファイルの文字コードを判定できませんでした。")
                    return
                }
                let result = UserDictionaryTextCodec.importEntries(from: text, format: importFormat)
                guard !result.entries.isEmpty else {
                    showAlert("有効な単語が見つかりませんでした。")
                    return
                }
                self.userDictionary.value.items.append(contentsOf: result.entries)
                editTargetID = nil
                undoItem = nil
                let skipped = result.skippedLineCount == 0 ? "" : " / \(result.skippedLineCount)行をスキップしました"
                showAlert("\(result.entries.count)件を読み込みました\(skipped)。")
            } catch {
                showAlert("読み込みに失敗しました: \(error.localizedDescription)")
            }
        }
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.title = "ユーザ辞書の書き出し"
        panel.nameFieldStringValue = "ユーザ辞書.txt"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let exported = UserDictionaryTextCodec.exportEntries(
                    self.userDictionary.value.items,
                    dictionaryName: "ユーザ辞書"
                )
                try Data(exported.utf8).write(to: url)
                showAlert("\(url.lastPathComponent)を書き出しました。")
            } catch {
                showAlert("書き出しに失敗しました: \(error.localizedDescription)")
            }
        }
    }

    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

#Preview {
    UserDictionaryEditorWindow()
}
