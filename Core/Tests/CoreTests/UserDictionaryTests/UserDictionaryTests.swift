@testable import Core
import Testing

@Test func testSystemUserDictionaryHelper() async throws {
    #if os(macOS)
    let entries = try await SystemUserDictionaryHelper.fetchEntries()
    print(entries)
    // always true
    #expect(entries.count >= 0)
    #else
    #expect(throws: SystemUserDictionaryHelper.FetchError.unsupportedOperatingSystem) {
        _ = try await SystemUserDictionaryHelper.fetchEntries()
    }
    #endif
}
