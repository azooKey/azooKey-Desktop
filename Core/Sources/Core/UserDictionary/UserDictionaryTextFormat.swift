import Foundation

public enum UserDictionaryTextFormat: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case googleJapaneseInput
    case msime
    case atok
    case kotoeri

    public var id: String {
        rawValue
    }

    public var localizedName: String {
        switch self {
        case .automatic:
            "自動判定"
        case .googleJapaneseInput:
            "Google日本語入力 / Mozc"
        case .msime:
            "Microsoft IME"
        case .atok:
            "ATOK"
        case .kotoeri:
            "ことえり"
        }
    }
}

public struct UserDictionaryImportResult: Sendable {
    public var dictionaryName: String?
    public var entries: [Config.UserDictionaryEntry]
    public var skippedLineCount: Int

    public init(dictionaryName: String?, entries: [Config.UserDictionaryEntry], skippedLineCount: Int) {
        self.dictionaryName = dictionaryName
        self.entries = entries
        self.skippedLineCount = skippedLineCount
    }
}

public enum UserDictionaryTextCodec {
    public static func decodeText(from data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: Data(data.dropFirst(3)), encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: Data(data.dropFirst(2)), encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return String(data: Data(data.dropFirst(2)), encoding: .utf16BigEndian)
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
            ?? String(data: data, encoding: .utf16)
    }

    public static func importEntries(
        from text: String,
        format requestedFormat: UserDictionaryTextFormat = .automatic
    ) -> UserDictionaryImportResult {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        let format = requestedFormat == .automatic ? guessFormat(from: lines) : requestedFormat
        var dictionaryName: String?
        var entries: [Config.UserDictionaryEntry] = []
        var skippedLineCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if let name = dictionaryNameHeader(in: trimmed) {
                dictionaryName = name
                continue
            }
            guard !isCommentOrHeader(trimmed, format: format) else {
                continue
            }

            let columns: [String]
            switch format {
            case .kotoeri:
                columns = splitCSV(trimmed)
            case .automatic, .googleJapaneseInput, .msime, .atok:
                columns = line.components(separatedBy: "\t")
            }

            guard columns.count >= 3 else {
                skippedLineCount += 1
                continue
            }
            let reading = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let word = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let hint = columns.count >= 4 ? normalizedHint(columns[3]) : nil
            guard !reading.isEmpty, !word.isEmpty else {
                skippedLineCount += 1
                continue
            }
            entries.append(.init(word: word, reading: reading, hint: hint))
        }

        return .init(dictionaryName: dictionaryName, entries: entries, skippedLineCount: skippedLineCount)
    }

    public static func exportEntries(_ entries: [Config.UserDictionaryEntry], dictionaryName: String) -> String {
        let header = [
            "!Dictionary File",
            "!Version: 1.0",
            "!User Dictionary Name: \(dictionaryName)"
        ]
        let body = entries.map { entry in
            [
                sanitizeField(entry.reading),
                sanitizeField(entry.word),
                "名詞",
                sanitizeField(entry.hint ?? "")
            ].joined(separator: "\t")
        }
        return (header + body).joined(separator: "\n") + "\n"
    }

    private static func dictionaryNameHeader(in line: String) -> String? {
        let prefix = "!User Dictionary Name:"
        guard line.hasPrefix(prefix) else {
            return nil
        }
        let name = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func isCommentOrHeader(_ line: String, format: UserDictionaryTextFormat) -> Bool {
        switch format {
        case .msime, .atok:
            line.hasPrefix("!")
        case .googleJapaneseInput, .automatic:
            line.hasPrefix("!") || line.hasPrefix("#")
        case .kotoeri:
            line.hasPrefix("//")
        }
    }

    private static func guessFormat(from lines: [String]) -> UserDictionaryTextFormat {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let lower = trimmed.lowercased()
            if lower.hasPrefix("!microsoft ime") {
                return .msime
            }
            if lower.hasPrefix("!!dicut") || lower.hasPrefix("!!atok_tango_text_header") {
                return .atok
            }
            if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), !trimmed.contains("\t") {
                return .kotoeri
            }
            if trimmed.hasPrefix("#") || trimmed.contains("\t") || trimmed.hasPrefix("!") {
                return .googleJapaneseInput
            }
        }
        return .googleJapaneseInput
    }

    private static func normalizedHint(_ value: String) -> String? {
        let hint = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return hint.isEmpty ? nil : hint
    }

    private static func sanitizeField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func splitCSV(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let nextIndex = line.index(after: index)
                if inQuotes, nextIndex < line.endIndex, line[nextIndex] == "\"" {
                    current.append("\"")
                    index = nextIndex
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(current)
        return fields
    }
}
