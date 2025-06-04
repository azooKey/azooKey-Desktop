import Foundation

/// カスタムローマ字テーブルの管理
public struct RomajiTable: Codable, Equatable, Hashable {
    public var mappings: [String: String]
    public var isEnabled: Bool
    
    public init(mappings: [String: String] = [:], isEnabled: Bool = false) {
        self.mappings = mappings
        self.isEnabled = isEnabled
    }
    
    /// デフォルトのローマ字テーブルを取得
    public static var defaultTable: RomajiTable {
        RomajiTable(mappings: [:], isEnabled: false)
    }
    
    /// DvorakJPローマ字テーブルの例
    public static var dvorakJPTable: RomajiTable {
        RomajiTable(mappings: [
            "ci": "か",
            "ce": "け",
            "jh;": "じゃん",
            "cu": "く",
            "co": "こ",
            "ca": "が",
            "qi": "し",
            "qe": "せ",
            "qu": "す",
            "qo": "そ",
            "qa": "ざ",
            "ji": "ち",
            "je": "て",
            "ju": "つ",
            "jo": "と",
            "ja": "だ",
            "xi": "に",
            "xe": "ね",
            "xu": "ぬ",
            "xo": "の",
            "xa": "な",
            "bi": "ひ",
            "be": "へ",
            "bu": "ふ",
            "bo": "ほ",
            "ba": "ば",
            "mi": "み",
            "me": "め",
            "mu": "む",
            "mo": "も",
            "ma": "ま",
            "wi": "り",
            "we": "れ",
            "wu": "る",
            "wo": "ろ",
            "wa": "ら",
            "vi": "ゆ",
            "ve": "よ",
            "vu": "や",
            "vo": "ゆ",
            "va": "ゆ"
        ], isEnabled: true)
    }
    
    /// ローマ字変換を実行
    public func convert(_ input: String) -> String? {
        guard isEnabled else { return nil }
        return mappings[input]
    }
    
    /// 指定した入力に対する変換候補があるかチェック
    public func hasPrefix(_ prefix: String) -> Bool {
        guard isEnabled else { return false }
        return mappings.keys.contains { $0.hasPrefix(prefix) }
    }
    
    /// 入力文字列に対して部分マッチする変換があるかチェック
    public func canStartConversion(with input: String) -> Bool {
        guard isEnabled else { return false }
        return mappings.keys.contains { key in
            key.hasPrefix(input) || input.hasPrefix(key)
        }
    }
    
    /// マッピングを追加
    public mutating func addMapping(from: String, to: String) {
        mappings[from] = to
    }
    
    /// マッピングを削除
    public mutating func removeMapping(from: String) {
        mappings.removeValue(forKey: from)
    }
    
    /// すべてのマッピングをクリア
    public mutating func clearMappings() {
        mappings.removeAll()
    }
    
    /// マッピング数を取得
    public var mappingCount: Int {
        mappings.count
    }
}

/// ローマ字テーブルの個別マッピング項目
public struct RomajiMapping: Codable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public var romaji: String
    public var kana: String
    
    public init(romaji: String, kana: String) {
        self.id = UUID()
        self.romaji = romaji
        self.kana = kana
    }
    
    public init(id: UUID = UUID(), romaji: String, kana: String) {
        self.id = id
        self.romaji = romaji
        self.kana = kana
    }
}

/// ローマ字テーブルのバリデーション
public enum RomajiTableValidationError: LocalizedError {
    case emptyRomaji
    case emptyKana
    case invalidRomajiCharacters
    case invalidKanaCharacters
    case duplicateRomaji
    
    public var errorDescription: String? {
        switch self {
        case .emptyRomaji:
            return "ローマ字が空です"
        case .emptyKana:
            return "ひらがなが空です"
        case .invalidRomajiCharacters:
            return "ローマ字に無効な文字が含まれています"
        case .invalidKanaCharacters:
            return "ひらがなに無効な文字が含まれています"
        case .duplicateRomaji:
            return "重複するローマ字があります"
        }
    }
}

extension RomajiTable {
    /// ローマ字テーブルのバリデーション
    public func validate() throws {
        for (romaji, kana) in mappings {
            if romaji.isEmpty {
                throw RomajiTableValidationError.emptyRomaji
            }
            if kana.isEmpty {
                throw RomajiTableValidationError.emptyKana
            }
            
            // ローマ字は英数字および一部の記号のみ許可（ASCII範囲に限定）
            let asciiAlphanumerics = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
            let allowedSymbols = CharacterSet(charactersIn: ";-")
            let romajiCharacterSet = asciiAlphanumerics.union(allowedSymbols)
            if !romaji.unicodeScalars.allSatisfy({ romajiCharacterSet.contains($0) }) {
                throw RomajiTableValidationError.invalidRomajiCharacters
            }
            
            // ひらがなの文字範囲をチェック
            let hiraganaRange: ClosedRange<UInt32> = 0x3040...0x309F
            if !kana.unicodeScalars.allSatisfy({ hiraganaRange.contains($0.value) }) {
                throw RomajiTableValidationError.invalidKanaCharacters
            }
        }
    }
}