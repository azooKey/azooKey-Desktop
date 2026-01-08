import Foundation

// Structure for prompt history item with pinned status
struct PromptHistoryItem: Sendable, Codable, Identifiable {
    var id: UUID = UUID()
    let prompt: String
    var isPinned: Bool = false
    var lastUsed: Date = Date()
    var shortcut: KeyboardShortcut?

    init(prompt: String, isPinned: Bool = false, shortcut: KeyboardShortcut? = nil) {
        self.prompt = prompt
        self.isPinned = isPinned
        self.lastUsed = Date()
        self.shortcut = shortcut
    }
}
