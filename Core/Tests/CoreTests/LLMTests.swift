import Core
import Testing

struct LLMProviderTypeTests {
    
    @Test func testFromString() {
        #expect(LLMProviderType(from: "openai") == .openai)
        #expect(LLMProviderType(from: "gemini") == .gemini)
        #expect(LLMProviderType(from: "custom") == .custom)
        #expect(LLMProviderType(from: "unknown") == .openai) // デフォルト
        #expect(LLMProviderType(from: "OPENAI") == .openai) // 大文字小文字
    }

    @Test func testDisplayName() {
        #expect(LLMProviderType.openai.displayName == "OpenAI")
        #expect(LLMProviderType.gemini.displayName == "Google Gemini")
        #expect(LLMProviderType.custom.displayName == "カスタム")
    }
}

struct LLMConfigurationTests {
    
    @Test func testDefaultEndpoint() throws {
        let openaiConfig = try LLMConfiguration(provider: .openai, apiKey: "test", modelName: "gpt-4")
        #expect(openaiConfig.endpoint == nil)

        let geminiConfig = try LLMConfiguration(provider: .gemini, apiKey: "test", modelName: "gemini-1.5-flash")
        #expect(geminiConfig.endpoint == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")

        let customConfig = try LLMConfiguration(provider: .custom, apiKey: "test", modelName: "model", endpoint: "https://custom.api.com")
        #expect(customConfig.endpoint == "https://custom.api.com")
    }
}

struct LLMClientFactoryTests {
    
    @Test func testClientCreation() throws {
        let openaiConfig = try LLMConfiguration(provider: .openai, apiKey: "test", modelName: "gpt-4")
        let openaiClient = LLMClientFactory.createClient(for: openaiConfig)
        #expect(openaiClient is OpenAIClientAdapter)

        let geminiConfig = try LLMConfiguration(provider: .gemini, apiKey: "test", modelName: "gemini-1.5-flash")
        let geminiClient = LLMClientFactory.createClient(for: geminiConfig)
        #expect(geminiClient is OpenAICompatibleClient)

        let customConfig = try LLMConfiguration(provider: .custom, apiKey: "test", modelName: "model", endpoint: "https://custom.api.com")
        let customClient = LLMClientFactory.createClient(for: customConfig)
        #expect(customClient is OpenAICompatibleClient)
    }
}

struct LLMResponseParserTests {

    @Test func testParseOpenAICompatibleResponse() throws {
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
            Issue.record("Failed to create test data")
            return
        }

        let result = try LLMResponseParser.parseOpenAICompatibleResponse(jsonData, logger: nil)
        #expect(result == ["test1", "test2"])
    }

    @Test func testParseOpenAITextResponse() throws {
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
            Issue.record("Failed to create test data")
            return
        }

        let result = try LLMResponseParser.parseOpenAITextResponse(jsonData)
        #expect(result == "Hello, world!")
    }

    @Test func testParseSimpleJSONArray() throws {
        let jsonString = """
        ["prediction1", "prediction2", "prediction3"]
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            Issue.record("Failed to create test data")
            return
        }

        let result = try LLMResponseParser.parseSimpleJSONArray(jsonData, logger: nil)
        #expect(result == ["prediction1", "prediction2", "prediction3"])
    }

    @Test func testParseInvalidJSON() {
        let invalidString = "invalid json"
        guard let invalidData = invalidString.data(using: .utf8) else {
            Issue.record("Failed to create test data")
            return
        }

        #expect(throws: (any Error).self) {
            try LLMResponseParser.parseOpenAICompatibleResponse(invalidData, logger: nil)
        }
        #expect(throws: (any Error).self) {
            try LLMResponseParser.parseOpenAITextResponse(invalidData)
        }
        #expect(throws: (any Error).self) {
            try LLMResponseParser.parseSimpleJSONArray(invalidData, logger: nil)
        }
    }
}