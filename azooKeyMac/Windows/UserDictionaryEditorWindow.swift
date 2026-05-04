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
    @State private var indexStatus: UserDictionaryIndexStatus = .notBuilt(entryCount: 0)
    @State private var indexBuildInProgress = false
    @State private var indexBuildMessage: String?
    @State private var indexBuildErrorMessage: String?
    @State private var scheduledIndexBuildTask: Task<Void, Never>?
    @State private var activeExportPanel: NSOpenPanel?
    @State private var presentingWindow: NSWindow?
    @State private var entrySearchText = ""
    @State private var entrySortOrder: [KeyPathComparator<Config.UserDictionaryEntry>] = []

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

    private var actionControlHeight: CGFloat {
        30
    }

    private var azooKeyMemoryDirectoryURL: URL {
        if #available(macOS 13, *) {
            URL.applicationSupportDirectory
                .appending(path: "azooKey", directoryHint: .isDirectory)
                .appending(path: "memory", directoryHint: .isDirectory)
        } else {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("azooKey", isDirectory: true)
                .appendingPathComponent("memory", isDirectory: true)
        }
    }

    private var presentationWindow: NSWindow? {
        presentingWindow ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible })
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
        .background(WindowAccessor(window: $presentingWindow))
        .frame(minHeight: 520, maxHeight: 760)
        .frame(minWidth: 900, maxWidth: 1_080)
        .onAppear {
            ensureSelection()
            refreshIndexStatus()
        }
        .onDisappear {
            scheduledIndexBuildTask?.cancel()
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(dictionaryValue.dictionaries.count)個の辞書 / \(totalItemCount)件の単語")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                Spacer()
            }

            indexStatusBar
            importExportBar
        }
        .padding(18)
    }

    private var indexStatusBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label(indexStatusTitle, systemImage: indexStatusSystemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(indexStatusColor)
                if indexBuildInProgress {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                }
                Text(indexStatusDetailText)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
                Spacer()
                ToolbarActionButton(title: "状態更新", systemImage: "arrow.clockwise", height: actionControlHeight, isEnabled: !indexBuildInProgress) { _ in
                    refreshIndexStatus()
                }
                ToolbarActionButton(
                    title: indexBuildErrorMessage == nil ? "今すぐ再作成" : "再実行",
                    systemImage: "arrow.triangle.2.circlepath",
                    height: actionControlHeight,
                    isEnabled: !indexBuildInProgress
                ) { _ in
                    rebuildIndexNow()
                }
            }
            Text(indexStatusMessageText)
                .font(.system(size: 12))
                .foregroundStyle(indexStatusMessageColor)
                .lineLimit(1)
                .frame(height: 16, alignment: .topLeading)
                .opacity(indexStatusMessageText.isEmpty ? 0 : 1)
        }
    }

    private var importExportBar: some View {
        HStack(spacing: 10) {
            Picker("形式", selection: $importFormat) {
                ForEach(UserDictionaryTextFormat.allCases) { format in
                    Text(format.localizedName).tag(format)
                }
            }
            .frame(width: 260)
            .frame(height: actionControlHeight)
            .controlSize(.regular)

            ToolbarActionButton(title: "新規辞書として読み込む", systemImage: "folder.badge.plus", height: actionControlHeight) { window in
                importFromFile(intoDictionaryID: nil, presentingWindow: window)
            }

            ToolbarActionButton(
                title: "選択辞書に追加",
                systemImage: "square.and.arrow.down",
                height: actionControlHeight,
                isEnabled: selectedDictionaryIDForActions != nil
            ) { window in
                importFromFile(intoDictionaryID: selectedDictionaryIDForActions, presentingWindow: window)
            }

            ToolbarActionButton(
                title: "選択辞書を書き出す",
                systemImage: "square.and.arrow.up",
                height: actionControlHeight,
                isEnabled: selectedDictionary != nil
            ) { window in
                exportSelectedDictionary(presentingWindow: window)
            }

            Spacer()
        }
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

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ToolbarActionButton(title: "追加", systemImage: "plus", height: actionControlHeight) { _ in
                        addDictionary()
                    }
                    ToolbarActionButton(title: "削除", systemImage: "trash", height: actionControlHeight, isEnabled: selectedDictionary != nil) { _ in
                        if let selectedDictionary {
                            deleteDictionaryTarget = selectedDictionary
                        }
                    }
                    Spacer()
                }
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
            entrySearchText = ""
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
                    HStack(spacing: 10) {
                        Button("単語を追加", systemImage: "plus") {
                            addEntry(to: selectedDictionary.id)
                        }
                        .frame(height: actionControlHeight)
                        if let undoItem {
                            Button("元に戻す", systemImage: "arrow.uturn.backward") {
                                restoreEntry(undoItem, to: selectedDictionary.id)
                            }
                            .frame(height: actionControlHeight)
                        }
                        Spacer()
                        entrySearchField
                    }
                    .controlSize(.regular)
                }

                Table(displayedItems(for: selectedDictionary), sortOrder: $entrySortOrder) {
                    TableColumn("") { item in
                        HStack(spacing: 6) {
                            Button("編集する", systemImage: "pencil") {
                                editTargetID = item.id
                                undoItem = nil
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                            .frame(height: actionControlHeight)

                            Button("削除する", systemImage: "trash", role: .destructive) {
                                removeEntry(item, from: selectedDictionary.id)
                            }
                            .buttonStyle(.bordered)
                            .labelStyle(.iconOnly)
                            .frame(height: actionControlHeight)
                        }
                    }
                    TableColumn("単語", value: \.word)
                    TableColumn("読み", value: \.reading)
                    TableColumn("コメント") { item in
                        Text(item.nonNullHint)
                            .lineLimit(1)
                    }
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

    private var entrySearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            TextField("単語・読み・コメントを検索", text: $entrySearchText)
                .textFieldStyle(.plain)
            if !entrySearchText.isEmpty {
                Button("検索を消去", systemImage: "xmark.circle.fill") {
                    entrySearchText = ""
                }
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 260, height: actionControlHeight)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private func displayedItems(for dictionary: Config.UserDictionaryGroup) -> [Config.UserDictionaryEntry] {
        let filteredItems = filteredItems(for: dictionary.items)
        guard !entrySortOrder.isEmpty else {
            return filteredItems
        }
        return filteredItems.sorted(using: entrySortOrder)
    }

    private func filteredItems(for items: [Config.UserDictionaryEntry]) -> [Config.UserDictionaryEntry] {
        let query = entrySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return items
        }
        return items.filter { item in
            item.word.localizedStandardContains(query)
                || item.reading.localizedStandardContains(query)
                || item.nonNullHint.localizedStandardContains(query)
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

            Text("この辞書内の単語だけを編集します。読み込みと書き出しはヘッダーの操作から実行します。")
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
                .frame(height: actionControlHeight)
            }
            .controlSize(.regular)
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
            updateUserDictionary(scheduleIndexRebuild: false, refreshIndexStatusWhenSkipped: false) { value in
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

    private func updateUserDictionary(
        scheduleIndexRebuild: Bool = true,
        refreshIndexStatusWhenSkipped: Bool = true,
        _ update: (inout Config.UserDictionary.Value) -> Void
    ) {
        var value = dictionaryValue
        update(&value)
        self.$userDictionary.wrappedValue = value
        if scheduleIndexRebuild {
            scheduleIndexRebuildSoon()
        } else if refreshIndexStatusWhenSkipped {
            refreshIndexStatus()
        }
    }

    private func ensureSelection() {
        if selectedDictionaryID == nil || selectedDictionary == nil {
            selectedDictionaryID = dictionaryValue.dictionaries.first?.id
        }
    }

    private func addDictionary() {
        let dictionary = Config.UserDictionaryGroup(name: nextDictionaryName())
        updateUserDictionary(scheduleIndexRebuild: false, refreshIndexStatusWhenSkipped: false) {
            $0.dictionaries.append(dictionary)
        }
        selectedDictionaryID = dictionary.id
        editTargetID = nil
        undoItem = nil
        entrySearchText = ""
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
        entrySearchText = ""
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
        entrySearchText = ""
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

    private func importFromFile(intoDictionaryID dictionaryID: UUID?, presentingWindow: NSWindow? = nil) {
        let panel = NSOpenPanel()
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
                entrySearchText = ""
                let skipped = result.skippedLineCount == 0 ? "" : " / \(result.skippedLineCount)行をスキップしました"
                showAlert("\(result.entries.count)件を読み込みました\(skipped)。")
            } catch {
                showAlert("読み込みに失敗しました: \(error.localizedDescription)")
            }
        }

        if let window = presentingWindow ?? presentationWindow {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    private func exportSelectedDictionary(presentingWindow: NSWindow? = nil) {
        guard let selectedDictionary else {
            showAlert("書き出す辞書を選択してください。")
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        let dictionaryName = selectedDictionary.name.isEmpty ? "ユーザ辞書" : selectedDictionary.name
        let items = selectedDictionary.items
        let fileNameField = exportFileNameField(defaultFileName: "\(dictionaryName).txt")
        panel.accessoryView = fileNameField.container
        panel.title = "ユーザ辞書の書き出し先を選択"
        panel.message = "書き出し先のフォルダを選び、ファイル名を指定してください。"
        panel.prompt = "書き出す"

        activeExportPanel = panel
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            activeExportPanel = nil
            guard response == .OK, let directoryURL = panel.url else {
                return
            }
            let destinationURL = directoryURL.appendingPathComponent(normalizedExportFileName(fileNameField.textField.stringValue))
            do {
                let canAccessDirectory = directoryURL.startAccessingSecurityScopedResource()
                defer {
                    if canAccessDirectory {
                        directoryURL.stopAccessingSecurityScopedResource()
                    }
                }
                let exported = UserDictionaryTextCodec.exportEntries(
                    items,
                    dictionaryName: dictionaryName
                )
                try Data(exported.utf8).write(to: destinationURL)
                indexBuildMessage = "「\(destinationURL.lastPathComponent)」を書き出しました。"
            } catch {
                showAlert("書き出しに失敗しました: \(error.localizedDescription)")
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        if let window = presentingWindow ?? presentationWindow {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    private func exportFileNameField(defaultFileName: String) -> (container: NSView, textField: NSTextField) {
        let label = NSTextField(labelWithString: "ファイル名:")
        let textField = NSTextField(string: defaultFileName)
        textField.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 32))
        container.addSubview(label)
        container.addSubview(textField)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            textField.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240)
        ])
        return (container, textField)
    }

    private func normalizedExportFileName(_ rawFileName: String) -> String {
        let trimmed = rawFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "ユーザ辞書.txt"
        let fileName = trimmed.isEmpty ? fallback : trimmed
        return fileName.lowercased().hasSuffix(".txt") ? fileName : "\(fileName).txt"
    }

    private var indexStatusTitle: String {
        if indexBuildInProgress {
            return "キャッシュ作成中"
        }
        if indexBuildErrorMessage != nil {
            return "キャッシュ作成失敗"
        }
        switch indexStatus {
        case .notBuilt:
            return "キャッシュ未作成"
        case .ready:
            return "キャッシュ最新"
        case .needsRebuild:
            return "キャッシュ更新が必要"
        }
    }

    private var indexStatusSystemImage: String {
        if indexBuildInProgress {
            return "clock.arrow.circlepath"
        }
        if indexBuildErrorMessage != nil {
            return "exclamationmark.triangle"
        }
        switch indexStatus {
        case .notBuilt:
            return "tray"
        case .ready:
            return "checkmark.circle"
        case .needsRebuild:
            return "arrow.triangle.2.circlepath"
        }
    }

    private var indexStatusColor: Color {
        if indexBuildErrorMessage != nil {
            return .red
        }
        switch indexStatus {
        case .ready:
            return .green
        case .notBuilt, .needsRebuild:
            return .secondary
        }
    }

    private var indexStatusMessageText: String {
        if let indexBuildErrorMessage {
            return indexBuildErrorMessage
        }
        return indexBuildMessage ?? ""
    }

    private var indexStatusMessageColor: Color {
        if indexBuildErrorMessage != nil {
            return .red
        }
        return Color(nsColor: .secondaryLabelColor)
    }

    private var indexStatusDetailText: String {
        if indexBuildInProgress {
            return "辞書を保存済みキャッシュへ反映しています。入力は続けられます。"
        }
        switch indexStatus {
        case .notBuilt(let entryCount):
            return "\(entryCount)件の有効な単語が対象です。"
        case .ready(let summary):
            return indexSummaryText(summary)
        case .needsRebuild(let currentEntryCount, let existing):
            if let existing {
                return "\(currentEntryCount)件の現在内容に対して更新が必要です。前回: \(indexSummaryText(existing))"
            }
            return "\(currentEntryCount)件の現在内容に対して更新が必要です。"
        }
    }

    private func indexSummaryText(_ summary: UserDictionaryIndexSummary) -> String {
        var parts = ["高速化済み: \(summary.indexedEntryCount)件"]
        if summary.skippedEntryCount > 0 {
            parts.append("直接検索: \(summary.skippedEntryCount)件")
        }
        if let updatedAt = summary.updatedAt {
            parts.append("更新: \(formattedIndexDate(updatedAt))")
        }
        return parts.joined(separator: " / ")
    }

    private func formattedIndexDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func refreshIndexStatus() {
        indexStatus = UserDictionaryIndexController.currentStatus(applicationDirectoryURL: azooKeyMemoryDirectoryURL)
        if case .ready = indexStatus {
            indexBuildErrorMessage = nil
        }
    }

    private func scheduleIndexRebuildSoon() {
        scheduledIndexBuildTask?.cancel()
        scheduledIndexBuildTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                refreshIndexStatus()
                rebuildIndexNow()
            }
        }
    }

    private func rebuildIndexNow() {
        guard !indexBuildInProgress else {
            return
        }
        scheduledIndexBuildTask?.cancel()
        indexBuildInProgress = true
        indexBuildErrorMessage = nil
        indexBuildMessage = nil
        let applicationDirectoryURL = azooKeyMemoryDirectoryURL
        Task {
            do {
                let result = try await Task.detached(priority: .utility) {
                    try UserDictionaryIndexController.rebuild(applicationDirectoryURL: applicationDirectoryURL)
                }.value
                await MainActor.run {
                    self.indexBuildInProgress = false
                    self.indexBuildMessage = self.indexBuildResultMessage(result)
                    self.refreshIndexStatus()
                }
            } catch {
                await MainActor.run {
                    self.indexBuildInProgress = false
                    self.indexBuildErrorMessage = "キャッシュ作成に失敗しました: \(error.localizedDescription)"
                    self.refreshIndexStatus()
                }
            }
        }
    }

    private func indexBuildResultMessage(_ result: UserDictionaryIndexBuildResult) -> String {
        if result.skippedEntryCount > 0 {
            return "\(result.indexedEntryCount)件を高速化用キャッシュに保存しました。\(result.skippedEntryCount)件は直接検索で候補に表示されます。"
        }
        return "\(result.indexedEntryCount)件を高速化用キャッシュに保存しました。"
    }

    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.window = nsView.window
        }
    }
}

private struct ToolbarActionButton: NSViewRepresentable {
    var title: String
    var systemImage: String
    var height: CGFloat
    var isEnabled: Bool = true
    var action: (NSWindow?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.performAction(_:)))
        button.bezelStyle = .rounded
        button.isBordered = true
        button.controlSize = .regular
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.contentTintColor = nil
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        context.coordinator.heightConstraint = button.heightAnchor.constraint(equalToConstant: height)
        context.coordinator.heightConstraint?.isActive = true
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        context.coordinator.heightConstraint?.constant = height
        button.title = title
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        button.isEnabled = isEnabled
    }

    final class Coordinator: NSObject {
        var action: (NSWindow?) -> Void
        var heightConstraint: NSLayoutConstraint?

        init(action: @escaping (NSWindow?) -> Void) {
            self.action = action
        }

        @objc func performAction(_ sender: NSButton) {
            action(sender.window)
        }
    }
}

#Preview {
    UserDictionaryEditorWindow()
}
