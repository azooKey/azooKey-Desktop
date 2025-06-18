import Core
import Testing

struct LLMProviderTypeParsingTests {
    @Test func testFromString() {
        #expect(LLMProviderType(from: "openai") == .openai)
        #expect(LLMProviderType(from: "gemini") == .gemini)
        #expect(LLMProviderType(from: "custom") == .custom)
        #expect(LLMProviderType(from: "unknown") == .openai) // デフォルトは OpenAI
    }
}

struct LLMResponseParserMinimalTests {
    @Test func testParseOpenAICompatibleResponse() throws {
        let jsonString = """
        {
            "choices": [
                {
                    "message": {
                        "content": "{\\\"predictions\\\": [\\\"test1\\\", \\\"test2\\\"]}"
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
        ["prediction1", "prediction2"]
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            Issue.record("Failed to create test data")
            return
        }
        let result = try LLMResponseParser.parseSimpleJSONArray(jsonData, logger: nil)
        #expect(result == ["prediction1", "prediction2"])
    }
}
