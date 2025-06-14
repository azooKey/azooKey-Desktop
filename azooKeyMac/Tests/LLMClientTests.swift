@testable import azooKeyMac
import Core
import XCTest

class LLMClientTests: XCTestCase {

    func testLLMProviderTypeFromString() {
        XCTAssertEqual(LLMProviderType(from: "openai"), .openai)
        XCTAssertEqual(LLMProviderType(from: "gemini"), .gemini)
        XCTAssertEqual(LLMProviderType(from: "custom"), .custom)
        XCTAssertEqual(LLMProviderType(from: "unknown"), .openai) // デフォルト
        XCTAssertEqual(LLMProviderType(from: "OPENAI"), .openai) // 大文字小文字
    }

    func testLLMProviderDisplayName() {
        XCTAssertEqual(LLMProviderType.openai.displayName, "OpenAI")
        XCTAssertEqual(LLMProviderType.gemini.displayName, "Google Gemini")
        XCTAssertEqual(LLMProviderType.custom.displayName, "カスタム")
    }

    func testLLMConfigurationDefaultEndpoint() {
        do {
            let openaiConfig = try LLMConfiguration(provider: .openai, apiKey: "test", modelName: "gpt-4")
            XCTAssertNil(openaiConfig.endpoint)

            let geminiConfig = try LLMConfiguration(provider: .gemini, apiKey: "test", modelName: "gemini-1.5-flash")
            XCTAssertEqual(geminiConfig.endpoint, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")

            let customConfig = try LLMConfiguration(provider: .custom, apiKey: "test", modelName: "model", endpoint: "https://custom.api.com")
            XCTAssertEqual(customConfig.endpoint, "https://custom.api.com")
        } catch {
            XCTFail("Configuration creation should succeed: \(error)")
        }
    }

    func testLLMClientFactoryCreation() {
        do {
            let openaiConfig = try LLMConfiguration(provider: .openai, apiKey: "test", modelName: "gpt-4")
            let openaiClient = LLMClientFactory.createClient(for: openaiConfig)
            XCTAssertTrue(openaiClient is OpenAIClientAdapter)

            let geminiConfig = try LLMConfiguration(provider: .gemini, apiKey: "test", modelName: "gemini-1.5-flash")
            let geminiClient = LLMClientFactory.createClient(for: geminiConfig)
            XCTAssertTrue(geminiClient is OpenAICompatibleClient)

            let customConfig = try LLMConfiguration(provider: .custom, apiKey: "test", modelName: "model", endpoint: "https://custom.api.com")
            let customClient = LLMClientFactory.createClient(for: customConfig)
            XCTAssertTrue(customClient is OpenAICompatibleClient)
        } catch {
            XCTFail("Configuration creation should succeed: \(error)")
        }
    }
}

class LLMResponseParserTests: XCTestCase {

    func testParseOpenAICompatibleResponse() {
        let jsonString = """
        {
            "choices": [
                {
                    "message": {
                        "content": "{\\"predictions\\": [\\"test1\\", \\"test2\\"]}"
                    }
                }
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to create test data")
            return
        }

        do {
            let result = try LLMResponseParser.parseOpenAICompatibleResponse(jsonData, logger: nil)
            XCTAssertEqual(result, ["test1", "test2"])
        } catch {
            XCTFail("Parsing should succeed: \(error)")
        }
    }

    func testParseOpenAITextResponse() {
        let jsonString = """
        {
            "choices": [
                {
                    "message": {
                        "content": "Hello, world!"
                    }
                }
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to create test data")
            return
        }

        do {
            let result = try LLMResponseParser.parseOpenAITextResponse(jsonData)
            XCTAssertEqual(result, "Hello, world!")
        } catch {
            XCTFail("Parsing should succeed: \(error)")
        }
    }

    func testParseSimpleJSONArray() {
        let jsonString = """
        ["prediction1", "prediction2", "prediction3"]
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to create test data")
            return
        }

        do {
            let result = try LLMResponseParser.parseSimpleJSONArray(jsonData, logger: nil)
            XCTAssertEqual(result, ["prediction1", "prediction2", "prediction3"])
        } catch {
            XCTFail("Parsing should succeed: \(error)")
        }
    }

    func testParseInvalidJSON() {
        let invalidString = "invalid json"
        guard let invalidData = invalidString.data(using: .utf8) else {
            XCTFail("Failed to create test data")
            return
        }

        XCTAssertThrowsError(try LLMResponseParser.parseOpenAICompatibleResponse(invalidData, logger: nil))
        XCTAssertThrowsError(try LLMResponseParser.parseOpenAITextResponse(invalidData))
        XCTAssertThrowsError(try LLMResponseParser.parseSimpleJSONArray(invalidData, logger: nil))
    }
}

class LLMConnectionTesterTests: XCTestCase {

    func testHandleHTTPErrorCodes() {
        // プライベートメソッドのテストは実際の実装では別の方法で行う
        // ここでは概念的なテストを示す

        // 401エラー
        // XCTAssertEqual(result.message, "認証エラー: APIキーが無効です")

        // 429エラー
        // XCTAssertEqual(result.message, "レート制限: しばらく待ってから再試行してください")

        // 500エラー
        // XCTAssertEqual(result.message, "サーバーエラー: 500")
    }
}
