import Testing
@testable import Core

struct KanaInputTests {
    @Test func testBasicKanaMapping() async throws {
        // 基本的なかな変換のテスト
        #expect(KeyMap.toKana("q") == "た")
        #expect(KeyMap.toKana("w") == "て")
        #expect(KeyMap.toKana("e") == "い")
        #expect(KeyMap.toKana("r") == "す")
        #expect(KeyMap.toKana("t") == "か")
        
        // 大文字でも同じ結果になることを確認
        #expect(KeyMap.toKana("Q") == "た")
        #expect(KeyMap.toKana("W") == "て")
        
        // 数字キーのテスト
        #expect(KeyMap.toKana("1") == "ぬ")
        #expect(KeyMap.toKana("2") == "ふ")
        #expect(KeyMap.toKana("3") == "あ")
        #expect(KeyMap.toKana("0") == "わ")
    }
    
    @Test func testShiftKanaMapping() async throws {
        // Shift + 数字で小書き文字
        #expect(KeyMap.toKana("3", shiftPressed: true) == "ぁ")
        #expect(KeyMap.toKana("4", shiftPressed: true) == "ぅ")
        #expect(KeyMap.toKana("5", shiftPressed: true) == "ぇ")
        #expect(KeyMap.toKana("6", shiftPressed: true) == "ぉ")
        #expect(KeyMap.toKana("7", shiftPressed: true) == "ゃ")
        #expect(KeyMap.toKana("8", shiftPressed: true) == "ゅ")
        #expect(KeyMap.toKana("9", shiftPressed: true) == "ょ")
        #expect(KeyMap.toKana("0", shiftPressed: true) == "を")
        
        // Shift + 文字キーで小書き文字
        #expect(KeyMap.toKana("e", shiftPressed: true) == "ぃ")
        #expect(KeyMap.toKana("z", shiftPressed: true) == "っ")
        #expect(KeyMap.toKana("v", shiftPressed: true) == "ゐ")
        
        // Shift + 記号で句読点など
        #expect(KeyMap.toKana(",", shiftPressed: true) == "、")
        #expect(KeyMap.toKana(".", shiftPressed: true) == "。")
        #expect(KeyMap.toKana("/", shiftPressed: true) == "・")
    }
    
    @Test func testSymbolMapping() async throws {
        // 記号キーのマッピング
        #expect(KeyMap.toKana("-") == "ほ")
        #expect(KeyMap.toKana("=") == "へ")
        #expect(KeyMap.toKana("[") == "゛")
        #expect(KeyMap.toKana("]") == "゜")
        #expect(KeyMap.toKana(";") == "れ")
        #expect(KeyMap.toKana("'") == "け")
        #expect(KeyMap.toKana(",") == "ね")
        #expect(KeyMap.toKana(".") == "る")
        #expect(KeyMap.toKana("/") == "め")
        #expect(KeyMap.toKana("`") == "ろ")
        #expect(KeyMap.toKana("\\") == "ー")
    }
    
    @Test func testUnmappedKeys() async throws {
        // マッピングされていないキーはnilを返す
        #expect(KeyMap.toKana("@") == nil)
        #expect(KeyMap.toKana("#") == nil)
        #expect(KeyMap.toKana("$") == nil)
        #expect(KeyMap.toKana("%") == nil)
        #expect(KeyMap.toKana("^") == nil)
        #expect(KeyMap.toKana("&") == nil)
        #expect(KeyMap.toKana("*") == nil)
        #expect(KeyMap.toKana("(") == nil)
        #expect(KeyMap.toKana(")") == nil)
    }
    
    @Test func testConvertToKanaString() async throws {
        // 文字列全体の変換テスト
        #expect(KeyMap.convertToKana("qwerty") == "たていすかん")
        // k->の, o->ら, n->み, n->み, i->に, c->そ, h->く, i->に, w->て, a->ち
        #expect(KeyMap.convertToKana("konnichiwa") == "のらみみにそくにてち")
        
        // 変換できない文字は残る
        #expect(KeyMap.convertToKana("q@w#e") == "た@て#い")
    }
    
    @Test func testNumberKeyMapping() async throws {
        // 数字キーの特別なテスト（getUserActionで処理される）
        #expect(KeyMap.toKana("1") == "ぬ")
        #expect(KeyMap.toKana("2") == "ふ")
        #expect(KeyMap.toKana("3") == "あ")
        #expect(KeyMap.toKana("4") == "う")
        #expect(KeyMap.toKana("5") == "え")
        #expect(KeyMap.toKana("6") == "お")
        #expect(KeyMap.toKana("7") == "や")
        #expect(KeyMap.toKana("8") == "ゆ")
        #expect(KeyMap.toKana("9") == "よ")
        #expect(KeyMap.toKana("0") == "わ")
    }
    
    @Test func testAllMappings() async throws {
        // 全ての基本マッピングが正しく定義されているか確認
        let expectedMappings = [
            // 数字
            "1": "ぬ", "2": "ふ", "3": "あ", "4": "う", "5": "え",
            "6": "お", "7": "や", "8": "ゆ", "9": "よ", "0": "わ",
            // 第1列
            "q": "た", "w": "て", "e": "い", "r": "す", "t": "か",
            "y": "ん", "u": "な", "i": "に", "o": "ら", "p": "せ",
            // 第2列
            "a": "ち", "s": "と", "d": "し", "f": "は", "g": "き",
            "h": "く", "j": "ま", "k": "の", "l": "り",
            // 第3列
            "z": "つ", "x": "さ", "c": "そ", "v": "ひ", "b": "こ",
            "n": "み", "m": "も"
        ]
        
        for (key, expectedKana) in expectedMappings {
            #expect(KeyMap.toKana(key) == expectedKana)
        }
    }
}