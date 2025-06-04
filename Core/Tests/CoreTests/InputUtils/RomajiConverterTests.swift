import Testing
import Foundation
import Core

@Test func testRomajiConverterManager() async throws {
    let initialTable = RomajiTable.dvorakJPTable
    var callbackCalled = false
    
    let manager = RomajiConverterManager(initialTable: initialTable) { _ in
        callbackCalled = true
    }
    
    #expect(manager.isCustomTableEnabled)
    
    // テーブル更新
    var newTable = RomajiTable()
    newTable.addMapping(from: "test", to: "テスト")
    newTable.isEnabled = true
    
    manager.updateCustomTable(newTable)
    #expect(callbackCalled)
    
    // 新しいテーブルでの変換テスト
    let result = manager.processInput("t")
    #expect(result == .buffering)
}

@Test func testRomajiConverterManagerBasicOperations() async throws {
    let table = RomajiTable.defaultTable
    let manager = RomajiConverterManager(initialTable: table) { _ in }
    
    #expect(manager.isEmpty)
    #expect(!manager.isCustomTableEnabled)
    
    // カスタムテーブルが無効な場合
    let result = manager.processInput("a")
    #expect(result == .converted("a"))
    #expect(manager.isEmpty)
}

@Test func testRomajiConverterComplexSequence() async throws {
    var table = RomajiTable()
    table.addMapping(from: "ka", to: "か")
    table.addMapping(from: "ki", to: "き")
    table.addMapping(from: "ku", to: "く")
    table.addMapping(from: "ke", to: "け")
    table.addMapping(from: "ko", to: "こ")
    table.isEnabled = true
    
    let converter = RomajiConverter(customTable: table)
    
    // 連続した変換のテスト
    var output = ""
    
    // "kakikukeko" を処理
    let input = "kakikukeko"
    for char in input {
        let result = converter.input(String(char))
        switch result {
        case .converted(let converted):
            output += converted
        case .buffering:
            // 継続
            break
        case .partialConversion(let converted, let remaining):
            output += converted
            // 残りの文字を再処理（実際の実装では InputController で行う）
            for remainingChar in remaining {
                let subResult = converter.input(String(remainingChar))
                if case .converted(let subConverted) = subResult {
                    output += subConverted
                }
            }
        }
    }
    
    // 最後にバッファをフラッシュ
    if let flushed = converter.flush() {
        output += flushed
    }
    
    #expect(output == "かきくけこ")
}

@Test func testRomajiConverterEdgeCases() async throws {
    var table = RomajiTable()
    table.addMapping(from: "a", to: "あ")
    table.addMapping(from: "aa", to: "ああ")
    table.isEnabled = true
    
    let converter = RomajiConverter(customTable: table)
    
    // 重複するプレフィックスのテスト
    let result1 = converter.input("a")
    #expect(result1 == .converted("あ")) // 単体でも変換される
    
    let result2 = converter.input("b") // "b"はそのまま出力
    #expect(result2 == .converted("b"))
}

@Test func testRomajiConverterLongSequence() async throws {
    var table = RomajiTable()
    table.addMapping(from: "jh;", to: "じゃん")
    table.isEnabled = true
    
    let converter = RomajiConverter(customTable: table)
    
    // 長いシーケンスのテスト
    var result1 = converter.input("j")
    #expect(result1 == .buffering)
    
    result1 = converter.input("h")
    #expect(result1 == .buffering)
    
    result1 = converter.input(";")
    #expect(result1 == .converted("じゃん"))
    
    #expect(converter.isEmpty)
}

@Test func testRomajiConverterDisabledTable() async throws {
    var table = RomajiTable()
    table.addMapping(from: "ci", to: "か")
    table.isEnabled = false // 無効
    
    let converter = RomajiConverter(customTable: table)
    
    // 無効な場合はそのまま出力
    let result = converter.input("c")
    #expect(result == .converted("c"))
    
    let result2 = converter.input("i")
    #expect(result2 == .converted("i"))
}

@Test func testConversionResultEquality() async throws {
    let result1 = RomajiConversionResult.converted("あ")
    let result2 = RomajiConversionResult.converted("あ")
    let result3 = RomajiConversionResult.converted("い")
    let result4 = RomajiConversionResult.buffering
    let result5 = RomajiConversionResult.partialConversion("あ", remaining: "い")
    let result6 = RomajiConversionResult.partialConversion("あ", remaining: "い")
    
    #expect(result1 == result2)
    #expect(result1 != result3)
    #expect(result1 != result4)
    #expect(result4 == RomajiConversionResult.buffering)
    #expect(result5 == result6)
}