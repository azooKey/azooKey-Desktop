import Core
import Testing

@Test func testEmojiDictionarySearchReturnsEmptyForEmptyQuery() async throws {
    #expect(EmojiDictionary.search(query: "").isEmpty)
}

@Test func testEmojiDictionarySearchFindsExactShortname() async throws {
    let results = EmojiDictionary.search(query: "smile")
    #expect(!results.isEmpty)
    #expect(results.contains { $0.shortnames.contains("smile") })
}

@Test func testEmojiDictionarySearchIsCaseInsensitive() async throws {
    let lower = EmojiDictionary.search(query: "smile")
    let upper = EmojiDictionary.search(query: "SMILE")
    #expect(!lower.isEmpty)
    #expect(!upper.isEmpty)
    #expect(lower.map(\.emoji) == upper.map(\.emoji))
}

@Test func testEmojiDictionarySearchPrefixMatchesPreferredOverSubstring() async throws {
    // "hand" で始まる shortname ("handshake" など) が、substring マッチよりも先に並ぶ
    let results = EmojiDictionary.search(query: "hand", limit: 30)
    #expect(results.count > 1)
    // 先頭数件は "hand" で始まるものがある
    let firstFew = results.prefix(3)
    #expect(firstFew.contains { entry in
        entry.shortnames.contains { $0.lowercased().hasPrefix("hand") }
    })
}

@Test func testEmojiDictionarySearchRespectsLimit() async throws {
    let results = EmojiDictionary.search(query: "e", limit: 5)
    #expect(results.count <= 5)
}

@Test func testEmojiDictionarySearchReturnsValidEmoji() async throws {
    let results = EmojiDictionary.search(query: "thumbsup")
    let entry = try #require(results.first { $0.shortnames.contains("+1") || $0.shortnames.contains("thumbsup") })
    // 絵文字が空でなく、Unicodeスカラが1つ以上含まれる
    #expect(!entry.emoji.isEmpty)
    #expect(entry.emoji.unicodeScalars.count >= 1)
}
