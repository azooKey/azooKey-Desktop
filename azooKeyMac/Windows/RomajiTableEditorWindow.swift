import Core
import KanaKanjiConverterModule
import SwiftUI

struct RomajiTableEditorWindow: View {
    struct InputTableLine: Sendable, Equatable, Hashable {
        var key: String
        var value: String
    }

    private static func tableToLines(_ table: InputTable) -> [InputTableLine] {
        if let exported = try? InputStyleManager.exportTable(table) {
            exported.components(separatedBy: "\n").compactMap { (line: String) -> InputTableLine? in
                let keyValuePair = line.components(separatedBy: "\t")
                guard keyValuePair.count == 2 else {
                    return nil
                }
                return InputTableLine(key: keyValuePair[0], value: keyValuePair[1])
            }
        } else {
            []
        }
    }

    init(base: InputTable? = nil, onSave: @escaping ((String) -> Void)) {
        if let base {
            self.lines = Self.tableToLines(base)
        } else {
            self.lines = []
        }
        self.onSave = onSave

        self._mappings = .init(initialValue: lines)
        self._shouldOpenBasePickerOnAppear = .init(initialValue: base == nil)
    }

    private let lines: [InputTableLine]
    private let onSave: ((String) -> Void)

    @State private var mappings: [InputTableLine] = []
    @State private var newRomaji: String = ""
    @State private var newKana: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var searchText = ""
    @State private var showingBasePicker = false
    @State private var shouldOpenBasePickerOnAppear = false
    @Environment(\.dismiss) private var dismiss

    private var filteredMappings: [InputTableLine] {
        guard !searchText.isEmpty else {
            return mappings
        }

        return mappings.filter { mapping in
            mapping.key.localizedCaseInsensitiveContains(searchText) ||
                mapping.value.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            headerView
            Divider()
            mappingInputView
            Divider()
            searchView
            mappingListView
            footerView
        }
        .padding()
        .frame(width: 600, height: 600)
        .onAppear {
            loadMappings()
            if shouldOpenBasePickerOnAppear {
                showingBasePicker = true
                // 一度出したらもう出さない
                shouldOpenBasePickerOnAppear = false
            }
        }
        .sheet(isPresented: $showingBasePicker) {
            basePickerView
        }
        .alert("エラー", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }

    private enum BasePreset: CaseIterable, Hashable {
        case `default`
        case azik
        case kanaJIS
        case kanaUS
        case empty

        var title: String {
            switch self {
            case .default: "デフォルト"
            case .azik: "AZIK（β版）"
            case .kanaJIS: "かな入力（JIS）"
            case .kanaUS: "かな入力（US）"
            case .empty: "Empty"
            }
        }
    }

    @ViewBuilder
    private var basePickerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ベースとなる入力テーブルを選択")
                .font(.headline)
            ForEach(BasePreset.allCases, id: \.self) { preset in
                Button(preset.title) {
                    applyPreset(preset)
                    showingBasePicker = false
                }
            }
            HStack {
                Spacer()
                Button("キャンセル") { showingBasePicker = false }
            }
        }
        .padding()
        .frame(width: 360)
    }

    @ViewBuilder
    private var headerView: some View {
        VStack {
            Text("カスタムローマ字テーブル")
                .font(.title)
                .bold()

            HStack {
                Button("初期値に戻す") {
                    loadMappings()
                }
                Button("すべてクリア") {
                    clearAllMappings()
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var mappingInputView: some View {
        VStack(alignment: .leading) {
            Text("新しいマッピングを追加")
                .font(.headline)

            HStack {
                TextField("ローマ字（例：ca）", text: $newRomaji)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 150)

                Image(systemName: "arrow.forward")

                TextField("ひらがな（例：か）", text: $newKana)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 150)

                Button("追加") {
                    addMapping()
                }
                .disabled(newRomaji.isEmpty)

                Spacer()
            }
        }
    }

    @ViewBuilder
    private var searchView: some View {
        HStack {
            TextField("検索...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            Text("マッピング数: \(mappings.count)")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var mappingListView: some View {
        VStack(alignment: .leading) {
            Text("現在のマッピング")
                .font(.headline)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredMappings, id: \.self) { mapping in
                        mappingRow(for: mapping)
                    }
                }
            }
            .frame(height: 300)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func mappingRow(for mapping: InputTableLine) -> some View {
        HStack {
            Text(mapping.key)
                .font(.system(.body, design: .monospaced))
                .frame(width: 200, alignment: .leading)

            Image(systemName: "arrow.forward")
                .foregroundColor(.secondary)

            Text(mapping.value)
                .frame(width: 200, alignment: .leading)

            Spacer()

            Button("削除", systemImage: "xmark.circle", role: .destructive) {
                removeMapping(mapping)
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(4)
    }

    @ViewBuilder
    private var footerView: some View {
        HStack {
            Button("キャンセル") {
                dismiss()
            }

            Spacer()

            Button("保存") {
                saveChanges()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func addMapping() {
        let trimmedRomaji = newRomaji.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKana = newKana.trimmingCharacters(in: .whitespacesAndNewlines)

        let checkResult = InputStyleManager.checkFormat(content: "\(trimmedRomaji)\t\(trimmedKana)")
        switch checkResult {
        case .fullyValid:
            // マッピングを追加
            let newMapping = InputTableLine(key: trimmedRomaji, value: trimmedKana)
            self.mappings.append(newMapping)
            // フィールドをクリア
            self.newRomaji = ""
            self.newKana = ""
        case .invalidLines(let errors):
            self.alertMessage = errors.map {
                "\($0)"
            }.joined()
            self.showingAlert = true
        }
    }

    private func removeMapping(_ mapping: InputTableLine) {
        mappings.removeAll { $0 == mapping }
    }

    private func clearAllMappings() {
        mappings.removeAll()
    }

    private func saveChanges() {
        // 変更をエクスポートして保存側へ通知
        let exported = mappings.map { "\($0.key)\t\($0.value)" }.joined(separator: "\n")
        onSave(exported)
    }

    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
    private func loadMappings() {
        self.mappings = self.lines
    }

    private func applyPreset(_ preset: BasePreset) {
        switch preset {
        case .empty:
            self.mappings = []
        case .default:
            self.mappings = Self.tableToLines(InputTable.defaultRomanToKana)
        case .azik:
            self.mappings = Self.tableToLines(InputTable.defaultAZIK)
        case .kanaJIS:
            self.mappings = Self.tableToLines(InputTable.defaultKanaJIS)
        case .kanaUS:
            self.mappings = Self.tableToLines(InputTable.defaultKanaUS)
        }
    }

    private static func parse(exported: String) -> [InputTableLine] {
        exported
            .components(separatedBy: "\n")
            .compactMap { line -> InputTableLine? in
                let pair = line.components(separatedBy: "\t")
                guard pair.count == 2 else { return nil }
                return .init(key: pair[0], value: pair[1])
            }
    }
}

#Preview {
    RomajiTableEditorWindow(base: .defaultRomanToKana) { _ in }
}
