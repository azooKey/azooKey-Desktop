import Foundation

public enum OptionDirectInputResolver {
    public static func resolve(
        characters: String?,
        modifierFlags: KeyEventCore.ModifierFlag,
        inputLanguage: InputLanguage,
        inputState: InputState,
        typeBackSlash: Bool
    ) -> String? {
        guard inputLanguage == .japanese, inputState == .none else {
            return nil
        }
        guard modifierFlags == [.option] || modifierFlags == [.option, .shift] else {
            return nil
        }
        guard let characters,
              !characters.isEmpty,
              isPrintable(characters)
        else {
            return nil
        }
        let normalized = normalize(characters, typeBackSlash: typeBackSlash)
        return normalized.applyingTransform(.fullwidthToHalfwidth, reverse: true)
    }

    private static func isPrintable(_ text: String) -> Bool {
        let printable: CharacterSet = [.alphanumerics, .symbols, .punctuationCharacters]
            .reduce(into: CharacterSet()) {
                $0.formUnion($1)
            }
        return CharacterSet(text.unicodeScalars).isSubset(of: printable)
    }

    private static func normalize(_ text: String, typeBackSlash: Bool) -> String {
        switch text {
        case "¥", "\\":
            typeBackSlash ? "\\" : "¥"
        default:
            text
        }
    }
}
