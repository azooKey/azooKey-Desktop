import KanaKanjiConverterModule

public extension Sequence where Element == InputPiece {
    func inputString(preferIntention: Bool = true) -> String {
        String(self.compactMap {
            switch $0 {
            case .character(let c):
                c
            case .key(intention: let intention, input: let input, modifiers: _):
                preferIntention ? (intention ?? input) : input
            case .compositionSeparator:
                nil
            }
        })
    }
}
