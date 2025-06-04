import Core
import SwiftUI

struct RomajiTableEditorWindow: View {
    @Binding var romajiTable: RomajiTable
    @State private var mappings: [RomajiMapping] = []
    @State private var newRomaji: String = ""
    @State private var newKana: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredMappings: [RomajiMapping] {
        guard !searchText.isEmpty else {
            return mappings
        }

        return mappings.filter { mapping in
            mapping.romaji.localizedCaseInsensitiveContains(searchText) ||
                mapping.kana.localizedCaseInsensitiveContains(searchText)
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
        }
        .alert("エラー", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }

    @ViewBuilder
    private var headerView: some View {
        VStack {
            Text("カスタムローマ字テーブル")
                .font(.title)
                .bold()

            HStack {
                Toggle("カスタムローマ字テーブルを有効化", isOn: Binding(
                    get: { romajiTable.isEnabled },
                    set: {
                        romajiTable.isEnabled = $0
                        updateRomajiTable()
                    }
                ))

                Spacer()

                Button("DvorakJPを読み込み") {
                    loadDvorakJPTable()
                }
                .disabled(!romajiTable.isEnabled)

                Button("すべてクリア") {
                    clearAllMappings()
                }
                .disabled(!romajiTable.isEnabled)
            }
        }
    }

    @ViewBuilder
    private var mappingInputView: some View {
        VStack(alignment: .leading) {
            Text("新しいマッピングを追加")
                .font(.headline)

            HStack {
                TextField("ローマ字（例：ci）", text: $newRomaji)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 150)
                    .disabled(!romajiTable.isEnabled)

                Text("→")

                TextField("ひらがな（例：か）", text: $newKana)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 150)
                    .disabled(!romajiTable.isEnabled)

                Button("追加") {
                    addMapping()
                }
                .disabled(newRomaji.isEmpty || newKana.isEmpty || !romajiTable.isEnabled)

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
                    ForEach(filteredMappings) { mapping in
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
    private func mappingRow(for mapping: RomajiMapping) -> some View {
        HStack {
            Text(mapping.romaji)
                .font(.system(.body, design: .monospaced))
                .frame(width: 100, alignment: .leading)

            Text("→")
                .foregroundColor(.secondary)

            Text(mapping.kana)
                .frame(width: 100, alignment: .leading)

            Spacer()

            Button("削除") {
                removeMapping(mapping)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
            .disabled(!romajiTable.isEnabled)
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

    private func loadMappings() {
        mappings = romajiTable.mappings.map { (romaji, kana) in
            RomajiMapping(romaji: romaji, kana: kana)
        }.sorted { $0.romaji < $1.romaji }
    }

    private func addMapping() {
        let trimmedRomaji = newRomaji.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKana = newKana.trimmingCharacters(in: .whitespacesAndNewlines)

        // バリデーション
        guard !trimmedRomaji.isEmpty && !trimmedKana.isEmpty else {
            showAlert("ローマ字とひらがなの両方を入力してください。")
            return
        }

        // 重複チェック
        if mappings.contains(where: { $0.romaji == trimmedRomaji }) {
            showAlert("そのローマ字はすでに登録されています。")
            return
        }

        // ローマ字の文字チェック（英数字および一部記号のみ）
        let asciiAlphanumerics = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let allowedSymbols = CharacterSet(charactersIn: ";-")
        let allowedCharacterSet = asciiAlphanumerics.union(allowedSymbols)
        if !trimmedRomaji.unicodeScalars.allSatisfy({ allowedCharacterSet.contains($0) }) {
            showAlert("ローマ字には英数字および「;」「-」のみ使用できます。")
            return
        }

        // ひらがなの文字チェック
        let hiraganaRange: ClosedRange<UInt32> = 0x3040...0x309F
        if !trimmedKana.unicodeScalars.allSatisfy({ hiraganaRange.contains($0.value) }) {
            showAlert("ひらがなのみ入力してください。")
            return
        }

        // マッピングを追加
        let newMapping = RomajiMapping(romaji: trimmedRomaji, kana: trimmedKana)
        mappings.append(newMapping)
        mappings.sort { $0.romaji < $1.romaji }

        // フィールドをクリア
        newRomaji = ""
        newKana = ""

        updateRomajiTable()
    }

    private func removeMapping(_ mapping: RomajiMapping) {
        mappings.removeAll { $0.id == mapping.id }
        updateRomajiTable()
    }

    private func loadDvorakJPTable() {
        let dvorakTable = RomajiTable.dvorakJPTable
        for (romaji, kana) in dvorakTable.mappings where !mappings.contains(where: { $0.romaji == romaji }) {
            mappings.append(RomajiMapping(romaji: romaji, kana: kana))
        }
        mappings.sort { $0.romaji < $1.romaji }
        updateRomajiTable()
    }

    private func clearAllMappings() {
        mappings.removeAll()
        updateRomajiTable()
    }

    private func updateRomajiTable() {
        var newMappings: [String: String] = [:]
        for mapping in mappings {
            newMappings[mapping.romaji] = mapping.kana
        }
        romajiTable.mappings = newMappings
    }

    private func saveChanges() {
        do {
            try romajiTable.validate()
            // 設定は自動的に保存される（@ConfigStateのため）
        } catch {
            showAlert("設定の保存に失敗しました: \(error.localizedDescription)")
        }
    }

    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

#Preview {
    RomajiTableEditorWindow(romajiTable: .constant(RomajiTable.dvorakJPTable))
}
