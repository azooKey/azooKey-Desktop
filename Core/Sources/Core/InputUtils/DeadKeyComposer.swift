public struct DeadKeyComposer {
    // Defines a struct to hold dead key mappings
    struct Combination: Hashable {
        let deadKey: String
        let combiningChar: String
        let lowercasedResult: String
        let uppercasedResult: String
    }

    // Defines dead key combinations as a static property
    static let combinations: Set<Combination> = [
        // Umlaut (¨)
        .init(deadKey: "¨", combiningChar: "a", lowercasedResult: "ä", uppercasedResult: "Ä"),
        .init(deadKey: "¨", combiningChar: "e", lowercasedResult: "ë", uppercasedResult: "Ë"),
        .init(deadKey: "¨", combiningChar: "i", lowercasedResult: "ï", uppercasedResult: "Ï"),
        .init(deadKey: "¨", combiningChar: "o", lowercasedResult: "ö", uppercasedResult: "Ö"),
        .init(deadKey: "¨", combiningChar: "u", lowercasedResult: "ü", uppercasedResult: "Ü"),
        .init(deadKey: "¨", combiningChar: "y", lowercasedResult: "ÿ", uppercasedResult: "Ÿ"),
        // Acute (´)
        .init(deadKey: "´", combiningChar: "a", lowercasedResult: "á", uppercasedResult: "Á"),
        .init(deadKey: "´", combiningChar: "e", lowercasedResult: "é", uppercasedResult: "É"),
        .init(deadKey: "´", combiningChar: "i", lowercasedResult: "í", uppercasedResult: "Í"),
        .init(deadKey: "´", combiningChar: "o", lowercasedResult: "ó", uppercasedResult: "Ó"),
        .init(deadKey: "´", combiningChar: "u", lowercasedResult: "ú", uppercasedResult: "Ú"),
        .init(deadKey: "´", combiningChar: "y", lowercasedResult: "ý", uppercasedResult: "Ý"),
        // Grave (`)
        .init(deadKey: "`", combiningChar: "a", lowercasedResult: "à", uppercasedResult: "À"),
        .init(deadKey: "`", combiningChar: "e", lowercasedResult: "è", uppercasedResult: "È"),
        .init(deadKey: "`", combiningChar: "i", lowercasedResult: "ì", uppercasedResult: "Ì"),
        .init(deadKey: "`", combiningChar: "o", lowercasedResult: "ò", uppercasedResult: "Ò"),
        .init(deadKey: "`", combiningChar: "u", lowercasedResult: "ù", uppercasedResult: "Ù"),
        // Circumflex (ˆ)
        .init(deadKey: "ˆ", combiningChar: "a", lowercasedResult: "â", uppercasedResult: "Â"),
        .init(deadKey: "ˆ", combiningChar: "e", lowercasedResult: "ê", uppercasedResult: "Ê"),
        .init(deadKey: "ˆ", combiningChar: "i", lowercasedResult: "î", uppercasedResult: "Î"),
        .init(deadKey: "ˆ", combiningChar: "o", lowercasedResult: "ô", uppercasedResult: "Ô"),
        .init(deadKey: "ˆ", combiningChar: "u", lowercasedResult: "û", uppercasedResult: "Û"),
        // Tilde (˜)
        .init(deadKey: "˜", combiningChar: "a", lowercasedResult: "ã", uppercasedResult: "Ã"),
        .init(deadKey: "˜", combiningChar: "n", lowercasedResult: "ñ", uppercasedResult: "Ñ"),
        .init(deadKey: "˜", combiningChar: "o", lowercasedResult: "õ", uppercasedResult: "Õ")
    ]

    public struct DeadKeyInfo: Sendable {
        public let deadKeyChar: String
    }

    public static let deadKeyList: [UInt16: DeadKeyInfo] = [
        0x20: DeadKeyInfo(deadKeyChar: "¨"), // 'u'
        0x0e: DeadKeyInfo(deadKeyChar: "´"), // 'e'
        0x32: DeadKeyInfo(deadKeyChar: "`"), // '`' (US layout)
        0x5e: DeadKeyInfo(deadKeyChar: "`"), // '_' (JIS layout)
        0x22: DeadKeyInfo(deadKeyChar: "ˆ"), // 'i'
        0x2d: DeadKeyInfo(deadKeyChar: "˜")  // 'n'
    ]

    // Attempts to combine a dead key with a character, returning the combined result
    static func combine(deadKey: String, with char: String, shift: Bool) -> String? {
        guard let combo = combinations.first(where: { $0.deadKey == deadKey && $0.combiningChar == char.lowercased() }) else {
            return nil
        }
        return shift ? combo.uppercasedResult : combo.lowercasedResult
    }
}
