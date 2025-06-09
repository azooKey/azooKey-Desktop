import Foundation

extension KeyMap {
    /// JISかな配列のキーマッピング（通常キー）
    public static let kanaInputMap: [String: String] = [
        // 数字キー
        "1": "ぬ",
        "2": "ふ",
        "3": "あ",
        "4": "う",
        "5": "え",
        "6": "お",
        "7": "や",
        "8": "ゆ",
        "9": "よ",
        "0": "わ",
        
        // 文字キー（第1列）
        "q": "た",
        "w": "て",
        "e": "い",
        "r": "す",
        "t": "か",
        "y": "ん",
        "u": "な",
        "i": "に",
        "o": "ら",
        "p": "せ",
        
        // 文字キー（第2列）
        "a": "ち",
        "s": "と",
        "d": "し",
        "f": "は",
        "g": "き",
        "h": "く",
        "j": "ま",
        "k": "の",
        "l": "り",
        
        // 文字キー（第3列）
        "z": "つ",
        "x": "さ",
        "c": "そ",
        "v": "ひ",
        "b": "こ",
        "n": "み",
        "m": "も",
        
        // 記号キー
        "-": "ほ",
        "=": "へ",
        "[": "゛",
        "]": "゜",
        ";": "れ",
        "'": "け",
        ",": "ね",
        ".": "る",
        "/": "め",
        "`": "ろ",
        "\\": "ー"  // JISキーボードの￥キー
    ]
    
    /// JISかな配列のキーマッピング（Shiftキー押下時）
    public static let kanaInputShiftMap: [String: String] = [
        // Shift + 数字
        "3": "ぁ",
        "4": "ぅ",
        "5": "ぇ",
        "6": "ぉ",
        "7": "ゃ",
        "8": "ゅ",
        "9": "ょ",
        "0": "を",
        
        // Shift + 文字キー（小書き文字）
        "e": "ぃ",
        "z": "っ",
        "v": "ゐ",
        
        // Shift + 記号
        "-": "ー",
        "=": "ゑ",
        "]": "「",
        "'": "ヶ",
        ",": "、",
        ".": "。",
        "/": "・"
    ]
    
    /// キーボード入力をかな文字に変換する
    /// - Parameters:
    ///   - key: 入力されたキー（小文字に正規化される）
    ///   - shiftPressed: Shiftキーが押されているかどうか
    /// - Returns: 対応するかな文字、マッピングがない場合はnil
    public static func toKana(_ key: String, shiftPressed: Bool = false) -> String? {
        let normalizedKey = key.lowercased()
        
        if shiftPressed {
            // Shiftキーが押されている場合、まずShiftマップを確認
            if let kana = kanaInputShiftMap[normalizedKey] {
                return kana
            }
        }
        
        // 通常のマップから取得
        return kanaInputMap[normalizedKey]
    }
    
    /// 文字列全体をかな入力モードで変換する
    /// - Parameter string: 入力文字列
    /// - Returns: 変換された文字列（変換できない文字はそのまま）
    public static func convertToKana(_ string: String) -> String {
        return string.map { char in
            if let kana = toKana(String(char)) {
                return kana
            }
            return String(char)
        }.joined()
    }
}