import Foundation

// Structure for prompt history item with pinned status
struct PromptHistoryItem: Sendable, Codable, Identifiable {
    var id: UUID = UUID()
    let prompt: String
    var isPinned: Bool = false
    var lastUsed: Date = Date()
    var shortcut: KeyboardShortcut?
    var isEisuDoubleTap: Bool = false  // 英数キーダブルタップ
    var isKanaDoubleTap: Bool = false  // かなキーダブルタップ

    init(prompt: String, isPinned: Bool = false, shortcut: KeyboardShortcut? = nil, isEisuDoubleTap: Bool = false, isKanaDoubleTap: Bool = false) {
        self.prompt = prompt
        self.isPinned = isPinned
        self.lastUsed = Date()
        self.shortcut = shortcut
        self.isEisuDoubleTap = isEisuDoubleTap
        self.isKanaDoubleTap = isKanaDoubleTap
    }
}
