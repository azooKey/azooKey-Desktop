import Core
import Testing

@Test func testMetadata() async throws {
    print("🏷️\tCurrent Git Tag   :", PackageMetadata.gitTag ?? "nil")
    print("🏷️\tCurrent Git Commit:", PackageMetadata.gitCommit ?? "nil")
    #expect(PackageMetadata.gitCommit != nil)
}
