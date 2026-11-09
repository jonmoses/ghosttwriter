import Testing
import WorkbenchProtocol
@testable import Ghostty

struct WorkbenchProtocolLinkTests {
    @Test func appLinksWorkbenchProtocol() {
        #expect(ClaudeColor.allCases.count == 8)
    }
}
