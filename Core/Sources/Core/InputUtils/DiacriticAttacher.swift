public struct DiacriticAttacher {
    // Set of characters that start a dead key sequence
    public static let deadKeyList: Set<String> = [
        "¨", "´", "`", "ˆ", "˜"
    ]

    // Maps a diacritic and a base character to its lowercase and uppercase result
    static let combinations: [String: [String: (String, String)]] = [
        "¨": [ // Umlaut
            "a": ("ä", "Ä"),
            "e": ("ë", "Ë"),
            "i": ("ï", "Ï"),
            "o": ("ö", "Ö"),
            "u": ("ü", "Ü"),
            "y": ("ÿ", "Ÿ")
        ],
        "´": [ // Acute
            "a": ("á", "Á"),
            "e": ("é", "É"),
            "i": ("í", "Í"),
            "o": ("ó", "Ó"),
            "u": ("ú", "Ú"),
            "y": ("ý", "Ý")
        ],
        "`": [ // Grave
            "a": ("à", "À"),
            "e": ("è", "È"),
            "i": ("ì", "Ì"),
            "o": ("ò", "Ò"),
            "u": ("ù", "Ù")
        ],
        "ˆ": [ // Circumflex
            "a": ("â", "Â"),
            "e": ("ê", "Ê"),
            "i": ("î", "Î"),
            "o": ("ô", "Ô"),
            "u": ("û", "Û")
        ],
        "˜": [ // Tilde
            "a": ("ã", "Ã"),
            "n": ("ñ", "Ñ"),
            "o": ("õ", "Õ")
        ]
    ]

    // Attempts to attach a diacritic to a base character, returning the attached result
    static func attach(deadKeyChar: String, with baseChar: String, shift: Bool) -> String? {
        guard let (lower, upper) = combinations[ deadKeyChar ]?[ baseChar.lowercased() ] else {
            return nil
        }
        return shift ? upper : lower
    }
}
