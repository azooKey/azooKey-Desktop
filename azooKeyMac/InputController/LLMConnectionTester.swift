import Foundation

enum LLMConnectionTestResult {
    case success(String)
    case failure(String)
}

struct LLMConnectionTester {
    static func testConnection(provider: LLMProviderType, apiKey: String, modelName: String, endpoint: String? = nil) async -> LLMConnectionTestResult {
        do {
            let configuration = createConfiguration(provider: provider, apiKey: apiKey, modelName: modelName, endpoint: endpoint)

            guard let client = LLMClientFactory.createClient(for: configuration) else {
                return .failure("設定が正しくありません。APIキーとモデル名を確認してください。")
            }

            // Simple test prompt
            let testPrompt = "Hello"
            let result = try await client.sendTextTransformRequest(prompt: testPrompt, modelName: modelName)

            return .success("接続成功: \(result.prefix(50))...")

        } catch let error as OpenAIError {
            return handleOpenAIError(error)
        } catch {
            return .failure("接続エラー: \(error.localizedDescription)")
        }
    }

    private static func createConfiguration(provider: LLMProviderType, apiKey: String, modelName: String, endpoint: String?) -> LLMConfiguration {
        LLMConfiguration(provider: provider, apiKey: apiKey, modelName: modelName, endpoint: endpoint)
    }

    private static func handleOpenAIError(_ error: OpenAIError) -> LLMConnectionTestResult {
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
}
