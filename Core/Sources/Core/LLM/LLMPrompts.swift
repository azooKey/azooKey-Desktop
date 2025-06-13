import Foundation

public struct LLMPrompts {
    public static let dictionary: [String: String] = [
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
        Input: "最高<るいぎご>"
        Output: ["素晴らしい", "素敵", "すごい", "良い", "優れている"]
        """,

        // いい感じ変換プロンプト
        "いいかんじ": """
        Transform the given text to sound better while preserving its meaning.
        Consider politeness, formality, and context appropriateness.
        Return 3-5 variations as a simple array of strings.

        Example:
        Input: "ちょっと分からない<いいかんじ>"
        Output: ["申し訳ございませんが、理解できません", "すみません、よくわかりません", "恐れ入りますが、不明です", "ごめんなさい、ちょっとわからないです", "理解が追いつきません"]
        """,

        // LaTeX/数式プロンプト
        "てふ": """
        Generate 3-5 LaTeX/mathematical expression options for the given context.
        Return them as a simple array of strings.

        Example:
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

    public static let sharedText = """
    Return 3-5 options as a simple array of strings, ordered from:
    - Most standard/common to more specific/creative
    - Most formal to more casual (where applicable)
    - Most direct to more nuanced interpretations
    """

    public static let defaultPrompt = """
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

    public static func getPromptText(for target: String) -> String {
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