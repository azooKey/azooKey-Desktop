import Foundation

private struct Prompt {
    static let dictionary: [String: String] = [
        // 文章補完プロンプト（デフォルト）
        "": """
        Generate 3-5 natural sentence completions for the given fragment.
        Return them as a simple array of strings.

        Example:
        Input: "りんごは"
        Output: ["赤いです。", "甘いです。", "美味しいです。", "1個200円です。", "果物です。"]
        """,

        // 絵文字変換プロンプト
        "えもじ": """
        Generate 3-5 emoji options that best represent the meaning of the text.
        Return them as a simple array of strings.

        Example:
        Input: "嬉しいです<えもじ>"
        Output: ["😊", "🥰", "😄", "💖", "✨"]
        """,

        // 顔文字変換プロンプト
        "かおもじ": """
        Generate 3-5 kaomoji (Japanese emoticon) options that best express the emotion or meaning of the text.
        Return them as a simple array of strings.

        Example:
        Input: "嬉しいです<かおもじ>"
        Output: ["(≧▽≦)", "(^_^)", "(o^▽^o)", "(｡♥‿♥｡)"]
        """,

        // 記号変換プロンプト
        "きごう": """
        Propose 3-5 symbol options to represent the given context.
        Return them as a simple array of strings.

        Example:
        Input: "総和<きごう>"
        Output: ["Σ", "+", "⊕"]
        """,

        // 類義語変換プロンプト
        "るいぎご": """
        Generate 3-5 synonymous word options for the given text.
        Return them as a simple array of Japanese strings.

        Example:
        Input: "楽しい<るいぎご>"
        Output: ["愉快", "面白い", "嬉しい", "快活", "ワクワクする"]
        """,

        // 対義語変換プロンプト
        "たいぎご": """
        Generate 3-5 antonymous word options for the given text.
        Return them as a simple array of Japanese strings.

        Example:
        Input: "楽しい<たいぎご>"
        Output: ["悲しい", "つまらない", "不愉快", "退屈", "憂鬱"]
        """,

        // TeXコマンド変換プロンプト
        "てふ": """
        Generate 3-5 TeX command options for the given mathematical content.
        Return them as a simple array of strings.

        Example:
        Input: "二次方程式<てふ>"
        Output: ["$x^2$", "$\\alpha$", "$\\frac{1}{2}$"]

        Input: "積分<てふ>"
        Output: ["$\\int$", "$\\oint$", "$\\sum$"]

        Input: "平方根<てふ>"
        Output: ["$\\sqrt{x}$", "$\\sqrt[n]{x}$", "$x^{1/2}$"]
        """,

        // 説明プロンプト
        "せつめい": """
        Provide 3-5 explanation to represent the given context.
        Return them as a simple array of Japanese strings.
        """,

        // つづきプロンプト
        "つづき": """
        Generate 2-5 short continuation options for the given context.
        Return them as a simple array of strings.

        Example:
        Input: "吾輩は猫である。<つづき>"
        Output: ["名前はまだない。", "名前はまだ無い。"]

        Example:
        Input: "10個の飴を5人に配る場合を考えます。<つづき>"
        Output: ["一人あたり10÷5=2個の飴を貰えます。", "1人2個の飴を貰えます。", "計算してみましょう"]

        Example:
        Input: "<つづき>"
        Output: ["👍"]
        """
    ]

    static let sharedText = """
    Return 3-5 options as a simple array of strings, ordered from:
    - Most standard/common to more specific/creative
    - Most formal to more casual (where applicable)
    - Most direct to more nuanced interpretations
    """

    static let defaultPrompt = """
    If the text in <> is a language name (e.g., <えいご>, <ふらんすご>, <すぺいんご>, <ちゅうごくご>, <かんこくご>, etc.),
    translate the preceding text into that language with 3-5 different variations.
    Otherwise, generate 3-5 alternative expressions of the text in <> that maintain its core meaning, following the sentence preceding <>.
    considering:
    - Different word choices
    - Varying formality levels
    - Alternative phrases or expressions
    - Different rhetorical approaches
    Return results as a simple array of strings.

    Example:
    Input: "おはようございます。今日も<てんき>"
    Output: ["いい天気", "雨", "晴れ", "快晴" , "曇り"]

    Input: "先日は失礼しました。<ごめん>"
    Output: ["すいません。", "ごめんなさい", "申し訳ありません"]

    Input: "すぐに戻ります<まってて>"
    Output: ["ただいま戻ります", "少々お待ちください", "すぐ参ります", "まもなく戻ります", "しばらくお待ちを"]

    Input: "遅刻してすいません。<いいわけ>"
    Output: ["電車の遅延", "寝坊", "道に迷って"]

    Input: "こんにちは<ふらんすご>"
    Output: ["Bonjour", "Salut", "Bon après-midi", "Coucou", "Allô"]

    Input: "ありがとう<すぺいんご>"
    Output: ["Gracias", "Muchas gracias", "Te lo agradezco", "Mil gracias", "Gracias mil"]
    """

    static func getPromptText(for target: String) -> String {
        let basePrompt = if let prompt = dictionary[target] {
            prompt
        } else if target.hasSuffix("えもじ") {
            """
            Generate 3-5 emoji options that best represent the meaning of "<\(target)>" in the context.
            Return them as a simple array of strings.
            Example:
            Input: "嬉しいです<はーとのえもじ>"
            Output: ["💖", "💕", "💓", "❤️", "💝"]
            Example:
            Input: "怒るよ<こわいえもじ>"
            Output: ["🔪", "👿", "👺", "💢", "😡"]
            """
        } else if target.hasSuffix("きごう") {
            """
            Generate 3-5 emoji options that best represent the meaning of "<\(target)>" in the context.
            Return them as a simple array of strings.
            Example:
            Input: "えー<びっくりきごう>"
            Output: ["！", "❗️", "❕"]
            Example:
            Input: "公式は<せきぶんきごう>"
            Output: ["∫", "∬", "∭", "∮"]
            """
        } else {
            defaultPrompt
        }
        return basePrompt + "\n\n" + sharedText
    }
}

// OpenAI APIに送信するリクエスト構造体。
//
// - properties:
//    - prompt: 変換対象の前のテキスト
//    - target: 変換対象のテキスト
//    - modelName: モデル名
//
// - methods:
//    - toJSON(): リクエストをOpenAI APIに適したJSON形式に変換する。
public struct OpenAIRequest {
    public init(prompt: String, target: String, modelName: String) {
        self.prompt = prompt
        self.target = target
        self.modelName = modelName
    }

    let prompt: String
    let target: String
    let modelName: String

    // リクエストをJSON形式に変換する関数
    func toJSON() -> [String: Any] {
        [
            "model": modelName,
            "messages": [
                ["role": "system", "content": "You are an assistant that predicts the continuation of short text."],
                ["role": "user", "content": """
                    \(Prompt.getPromptText(for: target))

                    `\(prompt)<\(target)>`
                    """]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "PredictionResponse", // 必須のnameフィールド
                    "schema": [ // 必須のschemaフィールド
                        "type": "object",
                        "properties": [
                            "predictions": [
                                "type": "array",
                                "items": [
                                    "type": "string",
                                    "description": "Replacement text"
                                ]
                            ]
                        ],
                        "required": ["predictions"],
                        "additionalProperties": false
                    ]
                ]
            ]
        ]
    }
}

public enum OpenAIError: LocalizedError, @unchecked Sendable {
    case invalidURL
    case noServerResponse
    case invalidResponseStatus(code: Int, body: String)
    case parseError(String)
    case invalidResponseStructure(Any)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not connect to OpenAI service. Please check your internet connection."
        case .noServerResponse:
            return "OpenAI service is not responding. Please try again later."
        case .invalidResponseStatus(let code, _):
            switch code {
            case 401:
                return "OpenAI API key is invalid. Please check your API key in preferences."
            case 403:
                return "Access denied by OpenAI. Please check your API key permissions."
            case 429:
                return "OpenAI rate limit exceeded. Please wait a moment and try again."
            case 500...599:
                return "OpenAI service is temporarily unavailable. Please try again later."
            default:
                return "OpenAI request failed. Please try again later."
            }
        case .parseError:
            return "Could not understand OpenAI response. Please try again."
        case .invalidResponseStructure:
            return "Received unexpected response from OpenAI. Please try again."
        }
    }
}

// OpenAI APIクライアント
public enum OpenAIClient {
    // APIリクエストを送信する静的メソッド
    public static func sendRequest(_ request: OpenAIRequest, apiKey: String, apiEndpoint: String, logger: ((String) -> Void)? = nil) async throws -> [String] {
        guard let url = URL(string: apiEndpoint) else {
            throw OpenAIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = request.toJSON()
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        // 非同期でリクエストを送信
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        // レスポンスの検証
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.noServerResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(bytes: data, encoding: .utf8) ?? "Body is not encoded in UTF-8"
            throw OpenAIError.invalidResponseStatus(code: httpResponse.statusCode, body: responseBody)
        }

        // レスポンスデータの解析
        return try parseResponseData(data, logger: logger)
    }

    // レスポンスデータのパースを行う静的メソッド
    private static func parseResponseData(_ data: Data, logger: ((String) -> Void)? = nil) throws -> [String] {
        logger?("Received JSON response")

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            logger?("Failed to parse JSON response")
            throw OpenAIError.parseError("Failed to parse response")
        }

        guard let jsonDict = jsonObject as? [String: Any],
              let choices = jsonDict["choices"] as? [[String: Any]] else {
            throw OpenAIError.invalidResponseStructure(jsonObject)
        }

        var allPredictions: [String] = []
        for choice in choices {
            guard let message = choice["message"] as? [String: Any],
                  let contentString = message["content"] as? String else {
                continue
            }

            logger?("Raw content string: \(contentString)")

            guard let contentData = contentString.data(using: .utf8) else {
                logger?("Failed to convert `content` string to data")
                continue
            }

            do {
                guard let parsedContent = try JSONSerialization.jsonObject(with: contentData) as? [String: [String]],
                      let predictions = parsedContent["predictions"] else {
                    logger?("Failed to parse `content` as expected JSON dictionary: \(contentString)")
                    continue
                }

                logger?("Parsed predictions: \(predictions)")
                allPredictions.append(contentsOf: predictions)
            } catch {
                logger?("Error parsing JSON from `content`: \(error.localizedDescription)")
            }
        }

        return allPredictions
    }

    // Simple text transformation method for AI Transform feature
    public static func sendTextTransformRequest(prompt: String, modelName: String, apiKey: String, apiEndpoint: String) async throws -> String {
        guard let url = URL(string: apiEndpoint) else {
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that transforms text according to user instructions. Return only the transformed text as a JSON object with a 'result' field."],
                ["role": "user", "content": prompt]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "TextTransformResponse",
                    "schema": [
                        "type": "object",
                        "properties": [
                            "result": [
                                "type": "string",
                                "description": "The transformed text"
                            ]
                        ],
                        "required": ["result"],
                        "additionalProperties": false
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Send async request
        let (data, response) = try await URLSession.shared.data(for: request)

        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.noServerResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(bytes: data, encoding: .utf8) ?? "Body is not encoded in UTF-8"
            throw OpenAIError.invalidResponseStatus(code: httpResponse.statusCode, body: responseBody)
        }

        // Parse response data using similar approach as sendRequest
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let jsonDict = jsonObject as? [String: Any],
              let choices = jsonDict["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let contentString = message["content"] as? String else {
            throw OpenAIError.invalidResponseStructure(jsonObject)
        }

        // Parse the structured JSON response
        guard let contentData = contentString.data(using: .utf8),
              let parsedContent = try JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let result = parsedContent["result"] as? String else {
            throw OpenAIError.parseError("Failed to parse structured response")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum ErrorUnion: Error {
    case nullError
    case double(any Error, any Error)
}

private struct ChatRequest: Codable {
    var model: String = "gpt-4o-mini"
    var messages: [Message] = []
}

private struct Message: Codable {
    enum Role: String, Codable {
        case user
        case system
        case assistant
    }
    var role: Role
    var content: String
}

private struct ChatSuccessResponse: Codable {
    var id: String
    var object: String
    var created: Int
    var model: String
    var choices: [Choice]

    struct Choice: Codable {
        var index: Int
        var logprobs: Double?
        var finishReason: String
        var message: Message
    }

    struct Usage: Codable {
        var promptTokens: Int
        var completionTokens: Int
        var totalTokens: Int
    }
}

private struct ChatFailureResponse: Codable, Error {
    var error: ErrorResponse
    struct ErrorResponse: Codable {
        var message: String
        var type: String
    }
}
