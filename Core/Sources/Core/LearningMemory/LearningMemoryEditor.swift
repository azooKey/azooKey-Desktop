import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

/// 履歴学習データを読み込み、選択した項目を削除する。
public enum LearningMemoryEditor {
    public enum EditorError: Error, CustomStringConvertible {
        case malformedMemory(String)
        case incompleteSave

        public var description: String {
            switch self {
            case .malformedMemory(let file): "学習データの形式が不正です: \(file)"
            case .incompleteSave: "学習データの保存が完了していません"
            }
        }
    }

    public struct Entry: Sendable, Equatable, Identifiable {
        public let ruby: String
        public let word: String
        public let lcid: Int
        public let rcid: Int
        public let mid: Int
        // メタデータと順位スコアを欠落なく復元するため、元のバイナリを保持する。
        let metadata: Data
        let score: Data

        public var count: Int { Int(metadata[4]) }
        public var lastUsedDay: Int { Int(metadata.load(UInt16.self, at: 0)) }
        public var lastUpdatedDay: Int { Int(metadata.load(UInt16.self, at: 2)) }

        public struct Key: Sendable, Hashable {
            let ruby: String
            let word: String
            let lcid: Int
            let rcid: Int
            let mid: Int
        }

        public var id: Key {
            .init(ruby: ruby, word: word, lcid: lcid, rcid: rcid, mid: mid)
        }

        /// 学習データの日付は「1970年1月1日からの日数 - 19000」で保存されている。
        public var lastUsedDate: Date {
            Date(timeIntervalSince1970: TimeInterval(lastUsedDay + 19000) * 86400)
        }

        var dicdataElement: DicdataElement {
            .init(word: word, ruby: ruby, lcid: lcid, rcid: rcid, mid: mid, value: 0)
        }
    }

    public struct Plan: Sendable {
        public let deleted: [Entry]
        // shortcut: 削除APIは表記単位なので、項目単位の削除APIが公開されるまでは残す項目を再登録する。
        public let readded: [Entry]

        public var isEmpty: Bool {
            deleted.isEmpty && readded.isEmpty
        }
    }

    public static func load(directoryURL: URL) throws -> [Entry] {
        try Self.loadMemory(directoryURL: directoryURL).entries
    }

    private static func loadMemory(directoryURL: URL, restoring: [Entry.ID: Entry] = [:]) throws -> (entries: [Entry], files: [(url: URL, data: Data)]) {
        guard !FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(".pause").path) else {
            throw EditorError.incompleteSave
        }
        let metadataFile = "memory.memorymetadata"
        // 一度も学習していない場合、ファイルは存在しない。
        guard FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(metadataFile).path) else {
            return ([], [])
        }
        var metadata = try Data(contentsOf: directoryURL.appendingPathComponent(metadataFile))
        guard metadata.count >= 4 else {
            throw EditorError.malformedMemory(metadataFile)
        }
        // 先頭4byteにノード数、各ノードに「項目数(1byte) + 項目数×(最終使用日, 最終更新日, 使用回数)」を保存する。
        let nodeCount = Int(metadata.load(UInt32.self, at: 0))
        guard nodeCount <= metadata.count - 4 else {
            throw EditorError.malformedMemory(metadataFile)
        }
        var metadataOffset = 4
        var readNodes = 0
        var entries: [Entry] = []
        var files: [(url: URL, data: Data)] = []
        var shard = 0
        while readNodes < nodeCount {
            let fileURL = directoryURL.appendingPathComponent("memory\(shard).loudstxt3")
            var data = try Data(contentsOf: fileURL)
            let result = try Self.loadShard(
                file: fileURL.lastPathComponent,
                data: &data,
                metadata: &metadata,
                metadataOffset: &metadataOffset,
                restoring: restoring
            )
            guard result.nodeCount <= nodeCount - readNodes else {
                throw EditorError.malformedMemory(fileURL.lastPathComponent)
            }
            entries += result.entries
            files.append((fileURL, data))
            readNodes += result.nodeCount
            shard += 1
        }
        guard metadataOffset == metadata.count else {
            throw EditorError.malformedMemory(metadataFile)
        }
        files.append((directoryURL.appendingPathComponent(metadataFile), metadata))
        return (entries, files)
    }

    private static func loadShard(file: String, data: inout Data, metadata: inout Data, metadataOffset: inout Int, restoring: [Entry.ID: Entry]) throws -> (nodeCount: Int, entries: [Entry]) {
        guard data.count >= 2 else {
            throw EditorError.malformedMemory(file)
        }
        let count = Int(data.load(UInt16.self, at: 0))
        guard count > 0, count <= (data.count - 2) / 4 else {
            throw EditorError.malformedMemory(file)
        }
        var entries: [Entry] = []
        for i in 0 ..< count {
            let start = Int(data.load(UInt32.self, at: 2 + 4 * i))
            let end = i + 1 < count ? Int(data.load(UInt32.self, at: 2 + 4 * (i + 1))) : data.count
            guard metadataOffset < metadata.count, start >= 2 + 4 * count, start + 2 <= end, end <= data.count else {
                throw EditorError.malformedMemory(file)
            }
            // 各ブロックは「項目数(2byte) + 項目数×(lcid, rcid, mid, value) + 読み\t表記\t…」の形式で保存する。
            let rowCount = Int(data.load(UInt16.self, at: start))
            let itemCount = Int(metadata[metadataOffset])
            let textStart = start + 2 + 10 * rowCount
            guard textStart <= end, let text = String(bytes: data[textStart ..< end], encoding: .utf8) else {
                throw EditorError.malformedMemory(file)
            }
            let fields = text.split(separator: "\t", omittingEmptySubsequences: false)
            guard itemCount == rowCount, fields.count == rowCount + 1,
                  metadataOffset + 1 + 5 * itemCount <= metadata.count else {
                throw EditorError.malformedMemory(file)
            }
            for k in 0 ..< rowCount {
                let row = start + 2 + 10 * k
                let meta = metadataOffset + 1 + 5 * k
                let ruby = String(fields[0])
                let entry = Entry(
                    ruby: ruby,
                    word: fields[k + 1].isEmpty ? ruby : String(fields[k + 1]),
                    lcid: Int(data.load(UInt16.self, at: row)),
                    rcid: Int(data.load(UInt16.self, at: row + 2)),
                    mid: Int(data.load(UInt16.self, at: row + 4)),
                    metadata: metadata.subdata(in: meta ..< meta + 5),
                    score: data.subdata(in: row + 6 ..< row + 10)
                )
                entries.append(entry)
                if let original = restoring[entry.id] {
                    metadata.replaceSubrange(meta ..< meta + 5, with: original.metadata)
                    data.replaceSubrange(row + 6 ..< row + 10, with: original.score)
                }
            }
            metadataOffset += 1 + 5 * itemCount
        }
        return (count, entries)
    }

    public static func plan(entries: [Entry], deleting selection: Set<Entry.ID>) -> Plan {
        let deleted = entries.filter { selection.contains($0.id) }
        let deletedWords = Set(deleted.map(\.word))
        let readded = entries.filter { !selection.contains($0.id) && deletedWords.contains($0.word) }
        return .init(deleted: deleted, readded: readded)
    }

    /// 入力中の変換状態を保持するため、削除には専用のセッションを使う。
    public static func apply(_ plan: Plan, directoryURL: URL, converter: KanaKanjiConverter) throws {
        guard !plan.isEmpty else {
            return
        }
        let session = converter.createSession()
        defer { converter.removeSession(session) }
        try converter.withSession(session) {
            // LearningConfigを直接生成できないため、変換要求で保存先と学習方式を指定する。
            var composingText = ComposingText()
            composingText.insertAtCursorPosition("あ", inputStyle: .direct)
            _ = converter.requestCandidates(composingText, options: .init(
                requireJapanesePrediction: .disabled,
                requireEnglishPrediction: .disabled,
                keyboardLanguage: .ja_JP,
                learningType: .inputAndOutput,
                memoryDirectoryURL: directoryURL,
                sharedContainerURL: CompiledUserDictionaryStore.directoryURL(memoryDirectoryURL: directoryURL),
                textReplacer: .empty,
                specialCandidateProviders: nil,
                metadata: nil
            ))
            converter.forgetMemory(Self.candidate(plan.deleted))
            for entry in plan.readded {
                // 項目同士の連結を学習しないよう、変換状態を初期化する。
                converter.stopComposition()
                converter.updateLearningData(Self.candidate([entry]))
            }
            converter.commitUpdateLearningData()
            try Self.restore(plan.readded, directoryURL: directoryURL)
        }
    }

    private static func restore(_ entries: [Entry], directoryURL: URL) throws {
        guard !entries.isEmpty else {
            return
        }
        let originals = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var files = try Self.loadMemory(directoryURL: directoryURL, restoring: originals).files
        for name in ["memory.loudschars2", "memory.louds"] {
            let url = directoryURL.appendingPathComponent(name)
            files.append((url, try Data(contentsOf: url)))
        }
        // エンジンと同じ保存手順に合わせ、途中で失敗しても .2 ファイルから復旧できるようにする。
        for (url, data) in files {
            try data.write(to: url.appendingPathExtension("2"), options: .atomic)
        }
        let pauseURL = directoryURL.appendingPathComponent(".pause")
        try Data().write(to: pauseURL, options: .atomic)
        for (url, data) in files {
            try data.write(to: url, options: .atomic)
        }
        try FileManager.default.removeItem(at: pauseURL)
    }

    /// 削除されなかった項目と、再登録されなかった項目を返す。
    public static func unapplied(_ plan: Plan, directoryURL: URL) throws -> Plan {
        let entries = Dictionary(try Self.load(directoryURL: directoryURL).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return .init(
            deleted: plan.deleted.filter { entries[$0.id] != nil },
            readded: plan.readded.filter { entries[$0.id] != $0 }
        )
    }

    private static func candidate(_ entries: [Entry]) -> Candidate {
        Candidate(
            text: entries.map(\.word).joined(),
            value: 0,
            composingCount: .surfaceCount(0),
            lastMid: entries.last?.mid ?? 0,
            data: entries.map(\.dicdataElement)
        )
    }
}

private extension Data {
    func load<T: FixedWidthInteger>(_: T.Type, at offset: Int) -> T {
        T(littleEndian: self.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) })
    }
}
