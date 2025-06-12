import Foundation
import OpenAI

struct Prompt {
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
struct OpenAIRequest {
    let prompt: String
    let target: String
    var modelName: String

    // 共通のJSON構造を生成するメソッド
    func toOpenAICompatibleJSON() -> [String: Any] {
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
                    "name": "PredictionResponse",
                    "schema": [
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

    // テキスト変換用のJSON構造を生成するメソッド
    static func createTextTransformJSON(prompt: String, modelName: String, maxTokens: Int = 150, temperature: Double = 0.7) -> [String: Any] {
        [
            "model": modelName,
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that transforms text according to user instructions."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens,
            "temperature": temperature
        ]
    }
}

enum OpenAIError: LocalizedError {
    case invalidURL
    case noServerResponse
    case invalidResponseStatus(code: Int, body: String)
    case parseError(String)
    case invalidResponseStructure(Any)

    var errorDescription: String? {
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
enum OpenAIClient {
    // APIリクエストを送信する静的メソッド
    static func sendRequest(_ request: OpenAIRequest, apiKey: String, logger: ((String) -> Void)? = nil) async throws -> [String] {
        let openAI = OpenAI(apiToken: apiKey)

        let query = ChatQuery(
            messages: [
                .system(.init(content: "You are an assistant that predicts the continuation of short text.")),
                .user(.init(content: .string("""
                    \(Prompt.getPromptText(for: request.target))

                    `\(request.prompt)<\(request.target)>`
                    """)))
            ],
            model: .init(request.modelName),
            responseFormat: .jsonObject
        )

        do {
            let result = try await openAI.chats(query: query)
            return try parseOpenAIResponse(result, logger: logger)
        } catch {
            throw mapOpenAIError(error)
        }
    }

    // MacPaw OpenAIライブラリのレスポンスを解析する静的メソッド
    private static func parseOpenAIResponse(_ response: ChatResult, logger: ((String) -> Void)? = nil) throws -> [String] {
        logger?("Received OpenAI response")

        var allPredictions: [String] = []
        for choice in response.choices {
            guard let contentString = choice.message.content else {
                continue
            }

            logger?("Raw content string: \(contentString)")

            guard let contentData = contentString.data(using: .utf8) else {
                logger?("Failed to convert content string to data")
                continue
            }

            do {
                guard let parsedContent = try JSONSerialization.jsonObject(with: contentData) as? [String: [String]],
                      let predictions = parsedContent["predictions"] else {
                    logger?("Failed to parse content as expected JSON dictionary: \(contentString)")
                    continue
                }

                logger?("Parsed predictions: \(predictions)")
                allPredictions.append(contentsOf: predictions)
            } catch {
                logger?("Error parsing JSON from content: \(error.localizedDescription)")
            }
        }

        return allPredictions
    }

    // MacPaw OpenAIライブラリのエラーをOpenAIErrorにマップする静的メソッド
    private static func mapOpenAIError(_ error: Error) -> OpenAIError {
        if let openAIError = error as? OpenAIError {
            return openAIError
        }

        // URLエラーの場合
        if error is URLError {
            return .noServerResponse
        }

        // その他のエラーは解析エラーとして扱う
        return .parseError(error.localizedDescription)
    }

    // Simple text transformation method for AI Transform feature
    static func sendTextTransformRequest(prompt: String, modelName: String, apiKey: String) async throws -> String {
        let openAI = OpenAI(apiToken: apiKey)

        let query = ChatQuery(
            messages: [
                .system(.init(content: "You are a helpful assistant that transforms text according to user instructions.")),
                .user(.init(content: .string(prompt)))
            ],
            model: .init(modelName),
            maxTokens: 150,
            temperature: 0.7
        )

        do {
            let result = try await openAI.chats(query: query)
            guard let firstChoice = result.choices.first,
                  let content = firstChoice.message.content else {
                throw OpenAIError.invalidResponseStructure(result)
            }

            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw mapOpenAIError(error)
        }
    }
}
