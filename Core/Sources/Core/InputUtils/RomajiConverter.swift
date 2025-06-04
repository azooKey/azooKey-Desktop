import Foundation

/// カスタムローマ字変換エンジン
public final class RomajiConverter {
    public let customTable: RomajiTable
    private var buffer: String = ""
    
    public init(customTable: RomajiTable = RomajiTable.defaultTable) {
        self.customTable = customTable
    }
    
    /// 文字を入力し、変換結果を返す
    /// - Parameter character: 入力文字
    /// - Returns: 変換結果 (nil の場合はバッファリング中)
    public func input(_ character: String) -> RomajiConversionResult {
        buffer += character
        
        guard customTable.isEnabled else {
            // カスタムテーブルが無効な場合は、すべてをそのまま出力
            let result = buffer
            buffer = ""
            return .converted(result)
        }
        
        // 完全一致を最初にチェック
        if let converted = customTable.convert(buffer) {
            let result = converted
            buffer = ""
            return .converted(result)
        }
        
        // 部分一致をチェック
        if customTable.hasPrefix(buffer) {
            return .buffering
        }
        
        // 一致しない場合の処理
        if buffer.count == 1 {
            // 1文字の場合はそのまま出力
            let result = buffer
            buffer = ""
            return .converted(result)
        } else {
            // 複数文字の場合、最初の文字を出力して残りを再処理
            let firstChar = String(buffer.first!)
            buffer = String(buffer.dropFirst())
            return .partialConversion(firstChar, remaining: buffer)
        }
    }
    
    /// バッファにある文字をフラッシュ（強制出力）
    public func flush() -> String? {
        guard !buffer.isEmpty else { return nil }
        let result = buffer
        buffer = ""
        return result
    }
    
    /// バッファの内容を取得
    public var currentBuffer: String {
        buffer
    }
    
    /// バッファをクリア
    public func clearBuffer() {
        buffer = ""
    }
    
    /// 一文字削除
    public func deleteLastCharacter() -> String? {
        guard !buffer.isEmpty else { return nil }
        let deleted = String(buffer.last!)
        buffer = String(buffer.dropLast())
        return deleted
    }
    
    /// バッファが空かどうか
    public var isEmpty: Bool {
        buffer.isEmpty
    }
}

/// ローマ字変換の結果
public enum RomajiConversionResult: Equatable {
    /// 変換完了
    case converted(String)
    /// バッファリング中（まだ変換できない）
    case buffering
    /// 部分変換（最初の部分が変換され、残りが再処理される）
    case partialConversion(String, remaining: String)
}

extension RomajiConverter {
    /// 文字列全体を処理する（デバッグ・テスト用）
    public func processString(_ input: String) -> String {
        var result = ""
        var remainingInput = input
        
        while !remainingInput.isEmpty {
            let char = String(remainingInput.first!)
            remainingInput = String(remainingInput.dropFirst())
            
            let conversionResult = self.input(char)
            
            switch conversionResult {
            case .converted(let converted):
                result += converted
            case .buffering:
                // 継続
                break
            case .partialConversion(let converted, let remaining):
                result += converted
                remainingInput = remaining + remainingInput
            }
        }
        
        // 最後にバッファをフラッシュ
        if let flushed = self.flush() {
            result += flushed
        }
        
        return result
    }
}

/// RomajiConverterのマネージャークラス
/// InputControllerで使用するためのヘルパー
public final class RomajiConverterManager {
    private var converter: RomajiConverter
    private let updateCallback: (RomajiTable) -> Void
    
    public init(initialTable: RomajiTable, updateCallback: @escaping (RomajiTable) -> Void) {
        self.converter = RomajiConverter(customTable: initialTable)
        self.updateCallback = updateCallback
    }
    
    /// カスタムテーブルを更新
    public func updateCustomTable(_ table: RomajiTable) {
        converter = RomajiConverter(customTable: table)
        updateCallback(table)
    }
    
    /// 文字入力処理
    public func processInput(_ character: String) -> RomajiConversionResult {
        converter.input(character)
    }
    
    /// バッファをフラッシュ
    public func flush() -> String? {
        converter.flush()
    }
    
    /// バッファをクリア
    public func clearBuffer() {
        converter.clearBuffer()
    }
    
    /// 一文字削除
    public func deleteLastCharacter() -> String? {
        converter.deleteLastCharacter()
    }
    
    /// 現在のバッファ
    public var currentBuffer: String {
        converter.currentBuffer
    }
    
    /// バッファが空かどうか
    public var isEmpty: Bool {
        converter.isEmpty
    }
    
    /// カスタムテーブルが有効かどうか
    public var isCustomTableEnabled: Bool {
        converter.customTable.isEnabled
    }
    
}