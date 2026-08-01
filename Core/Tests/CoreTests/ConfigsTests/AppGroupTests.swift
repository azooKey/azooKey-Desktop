import Foundation
import Testing

@testable import Core

#if os(macOS)
@Suite("AppGroup")
struct AppGroupTests {
    @Test("entitlementのないHelper向け共有コンテナURLを解決する")
    func resolveContainerURLFromHomeDirectory() {
        let homeDirectoryURL = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        #expect(
            AppGroup.containerURL(homeDirectoryURL: homeDirectoryURL).path
                == "/Users/example/Library/Group Containers/group.dev.ensan.inputmethod.azooKeyMac"
        )
    }
}
#endif
