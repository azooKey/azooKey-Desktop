import Core
import Testing

struct LLMTests {
    @Test func testProviderTypeInit() {
        #expect(LLMProviderType(from: "openai") == .openai)
        #expect(LLMProviderType(from: "gemini") == .gemini)
        #expect(LLMProviderType(from: "custom") == .custom)
        #expect(LLMProviderType(from: "unknown") == .openai)
    }
}
