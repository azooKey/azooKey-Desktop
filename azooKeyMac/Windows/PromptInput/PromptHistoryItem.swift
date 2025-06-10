//
//  PromptHistoryItem.swift
//  azooKeyMac
//
//  Created by Claude on 2025/06/10.
//

import Foundation

// Structure for prompt history item with pinned status
struct PromptHistoryItem: Codable {
    let prompt: String
    var isPinned: Bool = false
    var lastUsed: Date = Date()

    init(prompt: String, isPinned: Bool = false) {
        self.prompt = prompt
        self.isPinned = isPinned
        self.lastUsed = Date()
    }
}
