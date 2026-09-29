import Foundation

extension Config {
    public struct DateFormatPreference: CustomCodableConfigItem {
        public enum Value: String, Codable, Equatable, Hashable, Sendable {
            case standard
            case monthDay
            case weekday
        }

        public init() {}
        public static let `default`: Value = .standard
        public static let key = "dev.ensan.inputmethod.azooKeyMac.preference.dateFormatPreference"
    }
}
