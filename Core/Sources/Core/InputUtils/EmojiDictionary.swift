import Foundation

public struct EmojiEntry: Sendable, Hashable {
    public let emoji: String
    public let shortnames: [String]

    public init(emoji: String, shortnames: [String]) {
        self.emoji = emoji
        self.shortnames = shortnames
    }
}

public enum EmojiDictionary {
    public static func search(query: String, limit: Int = 30) -> [EmojiEntry] {
        let q = query.lowercased()
        if q.isEmpty {
            return []
        }
        var prefixMatches: [EmojiEntry] = []
        var substringMatches: [EmojiEntry] = []
        for entry in entries {
            var matched: Match = .none
            for key in entry.shortnames {
                let lk = key.lowercased()
                if lk.hasPrefix(q) {
                    matched = .prefix
                    break
                } else if lk.contains(q) {
                    matched = max(matched, .substring)
                }
            }
            switch matched {
            case .prefix:
                prefixMatches.append(entry)
            case .substring:
                substringMatches.append(entry)
            case .none:
                break
            }
            if prefixMatches.count >= limit {
                break
            }
        }
        let combined = prefixMatches + substringMatches
        return Array(combined.prefix(limit))
    }

    private enum Match: Int, Comparable {
        case none = 0, substring = 1, prefix = 2
        static func < (lhs: Match, rhs: Match) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    // iamcal/emoji-data の emoji.json をバンドルから読み込む。
    public static let entries: [EmojiEntry] = loadEntries()

    private struct RawEmoji: Decodable {
        let unified: String
        let short_names: [String]
        let sort_order: Int?
    }

    private static func loadEntries() -> [EmojiEntry] {
        guard let url = Bundle.module.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raws = try? JSONDecoder().decode([RawEmoji].self, from: data) else {
            return []
        }
        let sorted = raws.sorted { ($0.sort_order ?? Int.max) < ($1.sort_order ?? Int.max) }
        return sorted.compactMap { raw in
            guard let emoji = emojiString(fromUnified: raw.unified) else {
                return nil
            }
            return EmojiEntry(emoji: emoji, shortnames: raw.short_names)
        }
    }

    private static func emojiString(fromUnified unified: String) -> String? {
        let scalars = unified.split(separator: "-").compactMap { seg -> Unicode.Scalar? in
            guard let code = UInt32(seg, radix: 16) else {
                return nil
            }
            return Unicode.Scalar(code)
        }
        guard !scalars.isEmpty else {
            return nil
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
