import Foundation

// Structure for prompt history item with pinned status
struct PromptHistoryItem: Sendable, Codable, Identifiable {
    var id: UUID
    let prompt: String
    var isPinned: Bool
    var lastUsed: Date
    var shortcut: KeyboardShortcut?
    var isEisuDoubleTap: Bool
    var isKanaDoubleTap: Bool

    init(prompt: String, isPinned: Bool = false, shortcut: KeyboardShortcut? = nil, isEisuDoubleTap: Bool = false, isKanaDoubleTap: Bool = false) {
        self.id = UUID()
        self.prompt = prompt
        self.isPinned = isPinned
        self.lastUsed = Date()
        self.shortcut = shortcut
        self.isEisuDoubleTap = isEisuDoubleTap
        self.isKanaDoubleTap = isKanaDoubleTap
    }

    // 後方互換性のためのカスタムデコーダー
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.prompt = try container.decode(String.self, forKey: .prompt)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed) ?? Date()
        self.shortcut = try container.decodeIfPresent(KeyboardShortcut.self, forKey: .shortcut)
        self.isEisuDoubleTap = try container.decodeIfPresent(Bool.self, forKey: .isEisuDoubleTap) ?? false
        self.isKanaDoubleTap = try container.decodeIfPresent(Bool.self, forKey: .isKanaDoubleTap) ?? false
    }
}
