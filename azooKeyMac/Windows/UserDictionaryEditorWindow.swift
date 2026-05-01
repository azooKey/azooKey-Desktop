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

    @State private var selectedDictionaryID: UUID?
    @State private var editTargetID: UUID?
    @State private var undoItem: Config.UserDictionaryEntry?
    @State private var deleteDictionaryTarget: Config.UserDictionaryGroup?
    @State private var importFormat: UserDictionaryTextFormat = .automatic
    @State private var alertMessage = ""
    @State private var showingAlert = false

    private var dictionaryValue: Config.UserDictionary.Value {
        self.$userDictionary.wrappedValue
    }

    private var selectedDictionary: Config.UserDictionaryGroup? {
        if let selectedDictionaryID,
           let dictionary = dictionaryValue.dictionaries.first(where: { $0.id == selectedDictionaryID }) {
            return dictionary
        }
        return dictionaryValue.dictionaries.first
    }

    private var selectedDictionaryIDForActions: UUID? {
        selectedDictionary?.id
    }

    private var totalItemCount: Int {
        dictionaryValue.dictionaries.reduce(0) { $0 + $1.items.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 270)
                Divider()
                detailPane
            }
        }
        .font(.system(.body, design: .default))
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minHeight: 520, maxHeight: 760)
        .frame(minWidth: 900, maxWidth: 1_080)
        .onAppear {
            ensureSelection()
        }
        .alert("ユーザ辞書", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .alert(
            "辞書を削除しますか？",
            isPresented: Binding(
                get: { deleteDictionaryTarget != nil },
                set: {
                    if !$0 {
                        deleteDictionaryTarget = nil
                    }
                }
            )
        ) {
            Button("削除", role: .destructive) {
                deleteTargetDictionary()
            }
            Button("キャンセル", role: .cancel) {
                deleteDictionaryTarget = nil
            }
        } message: {
            if let deleteDictionaryTarget {
                Text("「\(deleteDictionaryTarget.name)」と、その中の\(deleteDictionaryTarget.items.count)件の単語を削除します。この操作は取り消せません。")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ユーザ辞書")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(dictionaryValue.dictionaries.count)個の辞書 / \(totalItemCount)件の単語")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Button("新規辞書", systemImage: "plus") {
                    addDictionary()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            HStack(spacing: 10) {
                Picker("読み込み形式", selection: $importFormat) {
                    ForEach(UserDictionaryTextFormat.allCases) { format in
                        Text(format.localizedName).tag(format)
                    }
                }
                .frame(width: 260)

                Button("新規辞書として読み込む", systemImage: "folder.badge.plus") {
                    importFromFile(intoDictionaryID: nil)
                }

                Button("選択辞書に追加", systemImage: "square.and.arrow.down") {
                    importFromFile(intoDictionaryID: selectedDictionaryIDForActions)
                }
                .disabled(selectedDictionaryIDForActions == nil)

                Spacer()

                Button("選択辞書を書き出す", systemImage: "square.and.arrow.up") {
                    exportSelectedDictionary()
                }
                .disabled(selectedDictionary == nil)
            }
        }
        .padding(18)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("辞書一覧")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.top, 14)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(dictionaryValue.dictionaries) { dictionary in
                        dictionaryRow(dictionary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }

            Divider()

            HStack(spacing: 8) {
                Button("追加", systemImage: "plus") {
                    addDictionary()
                }
                Button("削除", systemImage: "trash", role: .destructive) {
                    if let selectedDictionary {
                        deleteDictionaryTarget = selectedDictionary
                    }
                }
                .disabled(selectedDictionary == nil)
                Spacer()
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func dictionaryRow(_ dictionary: Config.UserDictionaryGroup) -> some View {
        let isSelected = selectedDictionary?.id == dictionary.id
        return HStack(spacing: 10) {
            Button(dictionary.isEnabled ? "無効にする" : "有効にする", systemImage: dictionary.isEnabled ? "checkmark.circle.fill" : "circle") {
                setDictionaryEnabled(dictionary.id, isEnabled: !dictionary.isEnabled)
            }
            .buttonStyle(.plain)
            .labelStyle(.iconOnly)
            .foregroundStyle(dictionary.isEnabled ? Color.accentColor : Color(nsColor: .secondaryLabelColor))

            VStack(alignment: .leading, spacing: 3) {
                Text(dictionary.name.isEmpty ? "名称未設定" : dictionary.name)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(dictionary.items.count)件")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        }
        .onTapGesture {
            selectedDictionaryID = dictionary.id
            editTargetID = nil
            undoItem = nil
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selectedDictionary {
            VStack(alignment: .leading, spacing: 14) {
                dictionarySummary(selectedDictionary)

                if let editTargetID {
                    editEntryForm(editTargetID: editTargetID, dictionaryID: selectedDictionary.id)
                } else {
                    HStack {
                        Button("単語を追加", systemImage: "plus") {
                            addEntry(to: selectedDictionary.id)
                        }
                        if let undoItem {
                            Button("元に戻す", systemImage: "arrow.uturn.backward") {
                                restoreEntry(undoItem, to: selectedDictionary.id)
                            }
                        }
                        Spacer()
                    }
                }

                Table(selectedDictionary.items) {
                    TableColumn("") { item in
                        HStack(spacing: 6) {
                            Button("編集する", systemImage: "pencil") {
                                editTargetID = item.id
                                undoItem = nil
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)

                            Button("削除する", systemImage: "trash", role: .destructive) {
                                removeEntry(item, from: selectedDictionary.id)
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                        }
                    }
                    TableColumn("単語", value: \.word)
                    TableColumn("読み", value: \.reading)
                    TableColumn("コメント", value: \.nonNullHint)
                }
            }
            .padding(18)
        } else {
            VStack(spacing: 12) {
                Text("辞書がありません")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Button("新規辞書を作成", systemImage: "plus") {
                    addDictionary()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func dictionarySummary(_ dictionary: Config.UserDictionaryGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                TextField("辞書名", text: dictionaryNameBinding(for: dictionary.id))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 16, weight: .medium))
                    .frame(minWidth: 240)

                Toggle("有効", isOn: dictionaryEnabledBinding(for: dictionary.id))
                    .toggleStyle(.checkbox)

                Spacer()

                Text("\(dictionary.items.count)件")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }

            Text("この辞書内の単語だけを編集します。読み込みと書き出しは画面上部の操作から実行します。")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        }
    }

    private func editEntryForm(editTargetID: UUID, dictionaryID: UUID) -> some View {
        let itemBinding = entryBinding(editTargetID: editTargetID, dictionaryID: dictionaryID)
        return VStack(alignment: .leading, spacing: 10) {
            Text("単語を編集")
                .font(.system(size: 14, weight: .semibold))
            HStack(spacing: 10) {
                TextField("単語", text: itemBinding.word)
                TextField("読み", text: itemBinding.reading)
                TextField("コメント", text: itemBinding.nonNullHint)
                Button("完了", systemImage: "checkmark") {
                    self.editTargetID = nil
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func dictionaryNameBinding(for dictionaryID: UUID) -> Binding<String> {
        Binding {
            dictionaryValue.dictionaries.first { $0.id == dictionaryID }?.name ?? ""
        } set: { newValue in
            updateUserDictionary { value in
                guard let index = value.dictionaries.firstIndex(where: { $0.id == dictionaryID }) else {
                    return
                }
                value.dictionaries[index].name = newValue
            }
        }
    }

    private func dictionaryEnabledBinding(for dictionaryID: UUID) -> Binding<Bool> {
        Binding {
            dictionaryValue.dictionaries.first { $0.id == dictionaryID }?.isEnabled ?? false
        } set: { isEnabled in
            setDictionaryEnabled(dictionaryID, isEnabled: isEnabled)
        }
    }

    private func entryBinding(editTargetID: UUID, dictionaryID: UUID) -> Binding<Config.UserDictionaryEntry> {
        Binding {
            dictionaryValue.dictionaries
                .first { $0.id == dictionaryID }?
                .items
                .first { $0.id == editTargetID } ?? .init(word: "", reading: "")
        } set: { newValue in
            updateUserDictionary { value in
                guard let dictionaryIndex = value.dictionaries.firstIndex(where: { $0.id == dictionaryID }),
                      let itemIndex = value.dictionaries[dictionaryIndex].items.firstIndex(where: { $0.id == editTargetID }) else {
                    return
                }
                value.dictionaries[dictionaryIndex].items[itemIndex] = newValue
            }
        }
    }

    private func updateUserDictionary(_ update: (inout Config.UserDictionary.Value) -> Void) {
        var value = dictionaryValue
        update(&value)
        self.$userDictionary.wrappedValue = value
    }

    private func ensureSelection() {
        if selectedDictionaryID == nil || selectedDictionary == nil {
            selectedDictionaryID = dictionaryValue.dictionaries.first?.id
        }
    }

    private func addDictionary() {
        let dictionary = Config.UserDictionaryGroup(name: nextDictionaryName())
        updateUserDictionary {
            $0.dictionaries.append(dictionary)
        }
        selectedDictionaryID = dictionary.id
        editTargetID = nil
        undoItem = nil
    }

    private func nextDictionaryName() -> String {
        let baseName = "新しい辞書"
        let existingNames = Set(dictionaryValue.dictionaries.map(\.name))
        guard existingNames.contains(baseName) else {
            return baseName
        }
        var number = 2
        while existingNames.contains("\(baseName) \(number)") {
            number += 1
        }
        return "\(baseName) \(number)"
    }

    private func setDictionaryEnabled(_ dictionaryID: UUID, isEnabled: Bool) {
        updateUserDictionary { value in
            guard let index = value.dictionaries.firstIndex(where: { $0.id == dictionaryID }) else {
                return
            }
            value.dictionaries[index].isEnabled = isEnabled
        }
    }

    private func deleteTargetDictionary() {
        guard let target = deleteDictionaryTarget else {
            return
        }
        updateUserDictionary {
            $0.dictionaries.removeAll { $0.id == target.id }
        }
        deleteDictionaryTarget = nil
        selectedDictionaryID = dictionaryValue.dictionaries.first?.id
        editTargetID = nil
        undoItem = nil
    }

    private func addEntry(to dictionaryID: UUID) {
        let newItem = Config.UserDictionaryEntry(word: "", reading: "", hint: nil)
        updateUserDictionary { value in
            guard let index = value.dictionaries.firstIndex(where: { $0.id == dictionaryID }) else {
                return
            }
            value.dictionaries[index].items.append(newItem)
        }
        editTargetID = newItem.id
        undoItem = nil
    }

    private func restoreEntry(_ item: Config.UserDictionaryEntry, to dictionaryID: UUID) {
        updateUserDictionary { value in
            guard let index = value.dictionaries.firstIndex(where: { $0.id == dictionaryID }) else {
                return
            }
            value.dictionaries[index].items.append(item)
        }
        undoItem = nil
    }

    private func removeEntry(_ item: Config.UserDictionaryEntry, from dictionaryID: UUID) {
        updateUserDictionary { value in
            guard let dictionaryIndex = value.dictionaries.firstIndex(where: { $0.id == dictionaryID }),
                  let itemIndex = value.dictionaries[dictionaryIndex].items.firstIndex(where: { $0.id == item.id }) else {
                return
            }
            undoItem = value.dictionaries[dictionaryIndex].items[itemIndex]
            value.dictionaries[dictionaryIndex].items.remove(at: itemIndex)
        }
    }

    private func importFromFile(intoDictionaryID dictionaryID: UUID?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .commaSeparatedText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "ユーザ辞書ファイルを選択"

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
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
                if let dictionaryID {
                    updateUserDictionary { value in
                        guard let index = value.dictionaries.firstIndex(where: { $0.id == dictionaryID }) else {
                            return
                        }
                        value.dictionaries[index].items.append(contentsOf: result.entries)
                    }
                    selectedDictionaryID = dictionaryID
                } else {
                    let fallbackName = url.deletingPathExtension().lastPathComponent
                    let dictionary = Config.UserDictionaryGroup(
                        name: result.dictionaryName ?? fallbackName,
                        isEnabled: true,
                        items: result.entries
                    )
                    updateUserDictionary {
                        $0.dictionaries.append(dictionary)
                    }
                    selectedDictionaryID = dictionary.id
                }
                editTargetID = nil
                undoItem = nil
                let skipped = result.skippedLineCount == 0 ? "" : " / \(result.skippedLineCount)行をスキップしました"
                showAlert("\(result.entries.count)件を読み込みました\(skipped)。")
            } catch {
                showAlert("読み込みに失敗しました: \(error.localizedDescription)")
            }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    private func exportSelectedDictionary() {
        guard let selectedDictionary else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(selectedDictionary.name).txt"
        panel.title = "ユーザ辞書を書き出し"

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            do {
                let exported = UserDictionaryTextCodec.exportEntries(
                    selectedDictionary.items,
                    dictionaryName: selectedDictionary.name
                )
                try Data(exported.utf8).write(to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                showAlert("書き出しに失敗しました: \(error.localizedDescription)")
            }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
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
