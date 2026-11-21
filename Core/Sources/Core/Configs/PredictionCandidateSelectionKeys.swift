import Foundation

extension Config {
    public struct PredictionCandidateSelectionKeys: ConfigItem {
        public enum Value: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
            case arrows
            case shift
            case command
            case option

            public var modifiers: KeyEventCore.ModifierFlag {
                switch self {
                case .arrows: []
                case .shift: .shift
                case .command: .command
                case .option: .option
                }
            }
        }

        public init() {}

        public static let `default`: Value = .shift
        public static let key = "dev.ensan.inputmethod.azooKeyMac.preference.predictionCandidateSelectionKeys"

        public var value: Value {
            get {
                Config.string(forKey: Self.key).flatMap(Value.init(rawValue:)) ?? Self.default
            }
            nonmutating set {
                Config.set(newValue.rawValue, forKey: Self.key)
            }
        }
    }
}
