import Foundation

public enum LLMConnectionTestResult: Sendable {
    case success(String)
    case failure(String)
}

public struct LLMConnectionTester {
    // エラーメッセージの最大長を定義
    private static let maxErrorMessageLength = 60
    
    public static func testConnection(provider: LLMProviderType, apiKey: String, modelName: String, endpoint: String? = nil) async -> LLMConnectionTestResult {
        do {
            let configuration = try createConfiguration(provider: provider, apiKey: apiKey, modelName: modelName, endpoint: endpoint)

            guard let client = LLMClientFactory.createClient(for: configuration) else {
                return .failure("設定が正しくありません。APIキーとモデル名を確認してください。")
            }

            // Simple test prompt
            let testPrompt = "Hello"
            let result = try await client.sendTextTransformRequest(prompt: testPrompt, modelName: modelName)

            let truncatedResult = truncateMessage(result, maxLength: 30)
            return .success("接続成功: \(truncatedResult)")

        } catch let error as LLMError {
            return handleLLMError(error)
        } catch let error as LLMConfigurationError {
            return handleConfigurationError(error)
        } catch {
            return handleGenericError(error)
        }
    }

    private static func createConfiguration(provider: LLMProviderType, apiKey: String, modelName: String, endpoint: String?) throws -> LLMConfiguration {
        try LLMConfiguration(provider: provider, apiKey: apiKey, modelName: modelName, endpoint: endpoint)
    }

    private static func handleLLMError(_ error: LLMError) -> LLMConnectionTestResult {
        switch error {
        case .invalidURL:
            return .failure("無効なURL")
        case .noServerResponse:
            return .failure("サーバーからの応答がありません")
        case .invalidResponseStatus(let code, _):
            return handleHTTPError(code: code)
        case .parseError(let message):
            return .failure("レスポンス解析エラー: \(message)")
        case .invalidResponseStructure:
            return .failure("レスポンス形式が無効です")
        }
    }

    private static func handleHTTPError(code: Int) -> LLMConnectionTestResult {
        switch code {
        case 401:
            return .failure("認証エラー: APIキーが無効です")
        case 403:
            return .failure("アクセス拒否: APIキーの権限を確認してください")
        case 429:
            return .failure("レート制限: しばらく待ってから再試行してください")
        case 500...599:
            return .failure("サーバーエラー: \(code)")
        default:
            return .failure("HTTPエラー: \(code)")
        }
    }

    private static func handleConfigurationError(_ error: LLMConfigurationError) -> LLMConnectionTestResult {
        switch error {
        case .invalidAPIKey:
            return .failure("APIキーが無効です")
        case .invalidModelName:
            return .failure("モデル名が無効です")
        case .invalidEndpoint:
            return .failure("エンドポイントURLが無効です")
        case .invalidMaxTokens:
            return .failure("最大トークン数が無効です")
        case .invalidTemperature:
            return .failure("温度設定が無効です")
        }
    }

    private static func handleGenericError(_ error: Error) -> LLMConnectionTestResult {
        // URLErrorの場合は簡潔なメッセージを返す
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return .failure("インターネット接続がありません")
            case .timedOut:
                return .failure("接続がタイムアウトしました")
            case .cannotFindHost:
                return .failure("サーバーが見つかりません")
            case .cannotConnectToHost:
                return .failure("サーバーに接続できません")
            default:
                return .failure("ネットワークエラーが発生しました")
            }
        }

        // その他のエラーは短縮して表示
        let errorMessage = error.localizedDescription
        let truncatedMessage = truncateMessage(errorMessage)
        return .failure("接続エラー: \(truncatedMessage)")
    }

    // エラーメッセージを指定長で切り詰めるヘルパー関数
    private static func truncateMessage(_ message: String, maxLength: Int? = nil) -> String {
        let limit = maxLength ?? maxErrorMessageLength
        if message.count <= limit {
            return message
        }
        return String(message.prefix(limit - 3)) + "..."
    }
}