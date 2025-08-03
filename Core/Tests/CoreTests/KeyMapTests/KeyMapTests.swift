import Core
import Testing

@Test func testh2z() async throws {
    // 半角文字→全角文字
    #expect(KeyMap.h2zMap("¥") == "￥")
    // 複数文字はサポートしない
    #expect(KeyMap.h2zMap("abc") == "abc")
}
