//
//  OpenAIService.swift
//  azooKeyMacOpenAIService
//

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

class OpenAIService: NSObject, OpenAIServiceProtocol {
    func sendRequest(
        prompt: String,
        mode: String,
        systemPrompt: String,
        model: String,
        apiKey: String,
        endpoint: String?,
        with reply: @escaping (String?, Error?) -> Void
    ) {
        Task {
            do {
                let result = try await performRequest(
                    prompt: prompt,
                    mode: mode,
                    systemPrompt: systemPrompt,
                    model: model,
                    apiKey: apiKey,
                    endpoint: endpoint
                )
                reply(result, nil)
            } catch {
                reply(nil, error)
            }
        }
    }
    
    func sendTextTransformRequest(
        text: String,
        prompt: String,
        context: String?,
        model: String,
        apiKey: String,
        endpoint: String?,
        with reply: @escaping (String?, Error?) -> Void
    ) {
        Task {
            do {
                let result = try await performTextTransformRequest(
                    text: text,
                    prompt: prompt,
                    context: context,
                    model: model,
                    apiKey: apiKey,
                    endpoint: endpoint
                )
                reply(result, nil)
            } catch {
                reply(nil, error)
            }
        }
    }
    
    private func performRequest(
        prompt: String,
        mode: String,
        systemPrompt: String,
        model: String,
        apiKey: String,
        endpoint: String?
    ) async throws -> String {
        let baseEndpoint = endpoint ?? "https://api.openai.com/v1"
        let url = URL(string: "\(baseEndpoint)/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build the user content with prompt template
        let promptText = Prompt.getPromptText(for: mode)
        let userContent = """
            \(promptText)
            
            `\(prompt)<\(mode)>`
            """
        
        let messages = [
            ["role": "system", "content": "You are an assistant that predicts the continuation of short text."],
            ["role": "user", "content": userContent]
        ]
        
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
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
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check HTTP response
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OpenAIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: responseBody])
        }
        
        // Parse the JSON response
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let contentString = message["content"] as? String,
           let contentData = contentString.data(using: .utf8),
           let parsedContent = try JSONSerialization.jsonObject(with: contentData) as? [String: [String]],
           let predictions = parsedContent["predictions"] {
            return predictions.joined(separator: "\n")
        }
        
        throw NSError(domain: "OpenAIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
    }
    
    private func performTextTransformRequest(
        text: String,
        prompt: String,
        context: String?,
        model: String,
        apiKey: String,
        endpoint: String?
    ) async throws -> String {
        let baseEndpoint = endpoint ?? "https://api.openai.com/v1"
        let url = URL(string: "\(baseEndpoint)/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = "You are a helpful assistant that transforms text based on user instructions. Only output the transformed text without any explanation."
        
        var userMessage = "Transform the following text according to this instruction: \(prompt)\n\nText to transform: \(text)"
        if let context = context {
            userMessage += "\n\nContext around the text: \(context)"
        }
        
        let messages = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userMessage]
        ]
        
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 500
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        throw NSError(domain: "OpenAIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
    }
}