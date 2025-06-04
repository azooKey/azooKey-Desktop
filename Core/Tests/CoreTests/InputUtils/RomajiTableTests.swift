import Testing
import Foundation
import Core

@Test func testRomajiTableBasicOperations() async throws {
    var table = RomajiTable()
    
    // 初期状態
    #expect(table.mappings.isEmpty)
    #expect(!table.isEnabled)
    #expect(table.mappingCount == 0)
    
    // マッピング追加
    table.addMapping(from: "ci", to: "か")
    #expect(table.mappingCount == 1)
    #expect(table.mappings["ci"] == "か")
    
    // マッピング削除
    table.removeMapping(from: "ci")
    #expect(table.mappingCount == 0)
    #expect(table.mappings["ci"] == nil)
}

@Test func testRomajiTableConversion() async throws {
    var table = RomajiTable()
    table.addMapping(from: "ci", to: "か")
    table.addMapping(from: "ce", to: "け")
    table.isEnabled = true
    
    // 変換テスト
    #expect(table.convert("ci") == "か")
    #expect(table.convert("ce") == "け")
    #expect(table.convert("ca") == nil)
    
    // 無効状態では変換されない
    table.isEnabled = false
    #expect(table.convert("ci") == nil)
}

@Test func testRomajiTablePrefixCheck() async throws {
    var table = RomajiTable()
    table.addMapping(from: "jh;", to: "じゃん")
    table.isEnabled = true
    
    // プレフィックスチェック
    #expect(table.hasPrefix("j"))
    #expect(table.hasPrefix("jh"))
    #expect(table.hasPrefix("jh;"))
    #expect(!table.hasPrefix("ji"))
    
    // 変換開始可能チェック
    #expect(table.canStartConversion(with: "j"))
    #expect(table.canStartConversion(with: "jh"))
    #expect(table.canStartConversion(with: "jh;"))
    #expect(!table.canStartConversion(with: "x"))
}

@Test func testRomajiTableValidation() async throws {
    var table = RomajiTable()
    
    // 正常なマッピング
    table.addMapping(from: "a", to: "あ")
    #expect(throws: Never.self) { try table.validate() }
    
    // 空のローマ字
    table.addMapping(from: "", to: "あ")
    #expect(throws: RomajiTableValidationError.self) { try table.validate() }
    
    // 無効なローマ字文字（日本語文字）
    table.clearMappings()
    table.addMapping(from: "あ", to: "あ")
    #expect(throws: RomajiTableValidationError.self) { try table.validate() }
    
    // 無効なローマ字文字（記号）
    table.clearMappings()
    table.addMapping(from: "@", to: "あ")
    #expect(throws: RomajiTableValidationError.self) { try table.validate() }
}

@Test func testRomajiTableDvorakJP() async throws {
    let dvorakTable = RomajiTable.dvorakJPTable
    
    #expect(dvorakTable.isEnabled)
    #expect(dvorakTable.mappingCount > 0)
    #expect(dvorakTable.convert("ci") == "か")
    #expect(dvorakTable.convert("ce") == "け")
    #expect(dvorakTable.convert("jh;") == "じゃん")
}

@Test func testRomajiConverter() async throws {
    let table = RomajiTable.dvorakJPTable
    let converter = RomajiConverter(customTable: table)
    
    // 完全一致
    let result1 = converter.input("c")
    #expect(result1 == .buffering)
    
    let result2 = converter.input("i")
    #expect(result2 == .converted("か"))
    
    // バッファが空になっていることを確認
    #expect(converter.isEmpty)
}

@Test func testRomajiConverterPartialConversion() async throws {
    var table = RomajiTable()
    table.addMapping(from: "ka", to: "か")
    table.isEnabled = true
    
    let converter = RomajiConverter(customTable: table)
    
    // 部分変換のテスト
    let result1 = converter.input("k")
    #expect(result1 == .buffering)
    
    let result2 = converter.input("i") // "ki"は登録されていない
    
    // "k"が出力され、"i"が残る
    if case .partialConversion(let converted, let remaining) = result2 {
        #expect(converted == "k")
        #expect(remaining == "i")
    } else {
        #expect(Bool(false), "Expected partialConversion")
    }
}

@Test func testRomajiConverterStringProcessing() async throws {
    var table = RomajiTable()
    table.addMapping(from: "ci", to: "か")
    table.addMapping(from: "ce", to: "け")
    table.isEnabled = true
    
    let converter = RomajiConverter(customTable: table)
    
    let result = converter.processString("cice")
    #expect(result == "かけ")
}

@Test func testRomajiConverterFlush() async throws {
    var table = RomajiTable()
    table.addMapping(from: "ci", to: "か")
    table.isEnabled = true
    
    let converter = RomajiConverter(customTable: table)
    
    // バッファリング状態を作る
    let result1 = converter.input("c")
    #expect(result1 == .buffering)
    #expect(!converter.isEmpty)
    
    // フラッシュ
    let flushed = converter.flush()
    #expect(flushed == "c")
    #expect(converter.isEmpty)
}

@Test func testRomajiConverterDeleteLastCharacter() async throws {
    var table = RomajiTable()
    table.addMapping(from: "ci", to: "か")
    table.isEnabled = true
    
    let converter = RomajiConverter(customTable: table)
    
    // バッファリング状態を作る
    let result1 = converter.input("c")
    #expect(result1 == .buffering)
    
    // 最後の文字を削除
    let deleted = converter.deleteLastCharacter()
    #expect(deleted == "c")
    #expect(converter.currentBuffer == "")
}

@Test func testRomajiMapping() async throws {
    let mapping1 = RomajiMapping(romaji: "ci", kana: "か")
    let mapping2 = RomajiMapping(romaji: "ce", kana: "け")
    
    #expect(mapping1.romaji == "ci")
    #expect(mapping1.kana == "か")
    #expect(mapping1.id != mapping2.id)
}

@Test func testRomajiTableCodable() async throws {
    let originalTable = RomajiTable.dvorakJPTable
    
    // エンコード
    let encoder = JSONEncoder()
    let data = try encoder.encode(originalTable)
    
    // デコード
    let decoder = JSONDecoder()
    let decodedTable = try decoder.decode(RomajiTable.self, from: data)
    
    #expect(originalTable == decodedTable)
}