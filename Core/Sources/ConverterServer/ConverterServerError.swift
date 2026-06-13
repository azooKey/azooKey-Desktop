import Foundation

enum ConverterServerError: LocalizedError {
    case unknownSession(String)
    case unknownSetting(String)
    case invalidSettingValue(String)

    var errorDescription: String? {
        switch self {
        case .unknownSession(let sessionID):
            "Unknown converter session: \(sessionID)"
        case .unknownSetting(let key):
            "Unknown converter setting: \(key)"
        case .invalidSettingValue(let key):
            "Invalid converter setting value: \(key)"
        }
    }
}
