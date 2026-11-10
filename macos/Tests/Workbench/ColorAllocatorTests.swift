import Testing
import WorkbenchProtocol
@testable import Ghostty

struct ColorAllocatorTests {
    @Test func picksLeastUsed() {
        var rng = SystemRandomNumberGenerator()
        let inUse: [ClaudeColor] = [.red, .blue, .green, .yellow, .purple, .orange, .pink]
        #expect(ColorAllocator.pick(inUse: inUse, using: &rng) == .cyan)
    }

    @Test func tieIsAmongLeastUsed() {
        var rng = SystemRandomNumberGenerator()
        let inUse: [ClaudeColor] = ClaudeColor.allCases + [.red, .blue]
        for _ in 0..<50 {
            let c = ColorAllocator.pick(inUse: inUse, using: &rng)
            #expect(c != .red && c != .blue)
        }
    }

    @Test func everyColorHasNSColor() {
        for c in ClaudeColor.allCases { _ = ColorAllocator.nsColor(c) }
    }
}
