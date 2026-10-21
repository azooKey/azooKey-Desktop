import Core
import KanaKanjiConverterModuleWithDefaultDictionary
import SwiftUI

/// 履歴学習データを検索し、選択した項目を削除する。
struct LearningMemoryEditorWindow: View {
    let converter: KanaKanjiConverter

    @State private var entries: [LearningMemoryEditor.Entry] = []
    @State private var query = ""
    @State private var selection = Set<LearningMemoryEditor.Entry.ID>()
    @State private var sortOrder = [KeyPathComparator(\LearningMemoryEditor.Entry.lastUsedDay, order: .reverse)]
    @State private var showingDeleteConfirmation = false
    @State private var message: String?

    private let memoryDirectoryURL = AppGroup.memoryDirectoryURL()

    private var shownEntries: [LearningMemoryEditor.Entry] {
        // 学習データの読みに合わせて、検索語をカタカナに変換する。
        let katakana = query.applyingTransform(.hiraganaToKatakana, reverse: false) ?? query
        return query.isEmpty ? entries : entries.filter { $0.word.contains(query) || $0.ruby.contains(katakana) }
    }

    private func deletionPlan(of entries: [LearningMemoryEditor.Entry]) -> LearningMemoryEditor.Plan {
        LearningMemoryEditor.plan(entries: entries, deleting: selection)
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("読みまたは表記で検索", text: $query)
                Text("\(shownEntries.count) / \(entries.count)件")
                    .monospacedDigit()
            }
            LearningMemoryTable(entries: shownEntries, selection: $selection, sortOrder: $sortOrder, onDelete: confirmDeletion)
            HStack {
                if let message {
                    Text(message)
                }
                Spacer()
                Button("再読み込み", action: reload)
                Button("選択した学習を削除", role: .destructive) {
                    confirmDeletion()
                }
                .disabled(selection.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
        .onAppear(perform: reload)
        // ウィンドウは閉じても再利用されるため、閉じる通知で結果を消す。
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if (notification.object as? NSWindow)?.contentViewController is NSHostingController<LearningMemoryEditorWindow> {
                message = nil
            }
        }
        // 表示中の項目だけを削除対象にするため、検索時に選択を解除する。
        .onChange(of: query) { _ in
            selection.removeAll()
        }
        .onChange(of: sortOrder) { order in
            entries.sort(using: order)
        }
        .confirmationDialog(
            "\(deletionPlan(of: entries).deleted.count)件の学習を削除しますか？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除", action: deleteSelection)
            Button("キャンセル", role: .cancel) {}
        } message: {
            let readdedCount = deletionPlan(of: entries).readded.count
            if readdedCount > 0 {
                Text("同じ表記を持つほかの\(readdedCount)件は、使用回数や日付を保持して復元されます。")
            }
        }
    }

    private func reload() {
        converter.commitUpdateLearningData()
        do {
            entries = try LearningMemoryEditor.load(directoryURL: memoryDirectoryURL).sorted(using: sortOrder)
            selection.formIntersection(Set(entries.map(\.id)))
        } catch {
            entries = []
            selection.removeAll()
            message = "学習データの読み込みに失敗しました: \(error)"
        }
    }

    private func confirmDeletion() {
        reload()
        showingDeleteConfirmation = !selection.isEmpty
    }

    private func deleteSelection() {
        do {
            // 未保存の学習を保存してから、削除対象と残す項目を確認する。
            converter.commitUpdateLearningData()
            let plan = deletionPlan(of: try LearningMemoryEditor.load(directoryURL: memoryDirectoryURL))
            try LearningMemoryEditor.apply(plan, directoryURL: memoryDirectoryURL, converter: converter)
            let unapplied = try LearningMemoryEditor.unapplied(plan, directoryURL: memoryDirectoryURL)
            message = unapplied.isEmpty
                ? "\(plan.deleted.count)件を削除しました"
                : "削除に失敗した項目が\(unapplied.deleted.count)件、再登録に失敗した項目が\(unapplied.readded.count)件あります。"
        } catch {
            message = "学習データの削除に失敗しました: \(error)"
        }
        reload()
        selection.removeAll()
    }
}
