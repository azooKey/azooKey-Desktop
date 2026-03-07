@testable import Core
import Testing

// 意図: OpenAI 向けの予測リクエスト JSON が現在の schema を維持していることを固定する。
@Test func testOpenAIRequestBuildsStrictPredictionSchema() throws {
    let request = OpenAIRequest(prompt: "前文", target: "えもじ", modelName: "gpt-test")
    let json = request.toJSON()

    let model = try #require(json["model"] as? String)
    #expect(model == "gpt-test")

    let messages = try #require(json["messages"] as? [[String: String]])
    #expect(messages.count == 2)
    #expect(messages[0]["role"] == "system")
    #expect(messages[1]["role"] == "user")
    #expect(messages[1]["content"]?.contains("前文<えもじ>") == true)

    let responseFormat = try #require(json["response_format"] as? [String: Any])
    #expect(responseFormat["type"] as? String == "json_schema")

    let jsonSchema = try #require(responseFormat["json_schema"] as? [String: Any])
    #expect(jsonSchema["name"] as? String == "prediction_response")
    #expect(jsonSchema["strict"] as? Bool == true)

    let schema = try #require(jsonSchema["schema"] as? [String: Any])
    let required = try #require(schema["required"] as? [String])
    #expect(required == ["predictions"])
}

// 意図: OpenAI の予測レスポンス parser が複数 choice の structured content を結合できることを固定する。
@Test func testOpenAIClientParsesPredictionsResponse() throws {
    let data = try #require(
        """
        {
          "choices": [
            { "message": { "content": "{\\"predictions\\":[\\"候補1\\",\\"候補2\\"]}" } },
            { "message": { "content": "{\\"predictions\\":[\\"候補3\\"]}" } }
          ]
        }
        """.data(using: .utf8)
    )

    let predictions = try OpenAIClient.parsePredictionsResponse(data)

    #expect(predictions == ["候補1", "候補2", "候補3"])
}

// 意図: OpenAI のテキスト変換レスポンス parser が result を trim して返すことを固定する。
@Test func testOpenAIClientParsesTrimmedTextTransformResponse() throws {
    let data = try #require(
        """
        {
          "choices": [
            { "message": { "content": "{\\"result\\":\\" 変換結果\\\\n\\"}" } }
          ]
        }
        """.data(using: .utf8)
    )

    let result = try OpenAIClient.parseTextTransformResponse(data)

    #expect(result == "変換結果")
}

// 意図: AIClient の OpenAI 経路が追加ロジックを持たず invalidURL をそのまま返すことを固定する。
@Test func testAIClientPredictionRequestPropagatesOpenAIInvalidURL() async throws {
    let request = OpenAIRequest(prompt: "前文", target: "えもじ", modelName: "gpt-test")
    let configuration = AIClient.configuration(
        for: .openAI,
        apiKey: "dummy",
        apiEndpoint: "ht^tp://example.com"
    )

    do {
        _ = try await AIClient.sendPrediction(
            request,
            using: configuration
        )
        Issue.record("Expected invalidURL to be thrown")
    } catch let error as OpenAIError {
        guard case .invalidURL = error else {
            Issue.record("Expected invalidURL, got \(error)")
            return
        }
    }
}

// 意図: AIClient の OpenAI テキスト変換経路が invalidURL をそのまま返すことを固定する。
@Test func testAIClientTextTransformPropagatesOpenAIInvalidURL() async throws {
    let request = AITextTransformRequest(prompt: "instruction", modelName: "gpt-test")
    let configuration = AIClient.configuration(
        for: .openAI,
        apiKey: "dummy",
        apiEndpoint: "ht^tp://example.com"
    )

    do {
        _ = try await AIClient.sendTextTransform(
            request,
            using: configuration
        )
        Issue.record("Expected invalidURL to be thrown")
    } catch let error as OpenAIError {
        guard case .invalidURL = error else {
            Issue.record("Expected invalidURL, got \(error)")
            return
        }
    }
}
