import AppKit
import WorkbenchProtocol

/// Chooses a Claude color for a new tab and maps colors to AppKit.
enum ColorAllocator {
    /// The least-used color among `inUse`, with ties broken at random.
    static func pick<R: RandomNumberGenerator>(inUse: [ClaudeColor], using rng: inout R) -> ClaudeColor {
        var counts = Dictionary(uniqueKeysWithValues: ClaudeColor.allCases.map { ($0, 0) })
        for c in inUse { counts[c, default: 0] += 1 }
        let least = counts.values.min()!
        return ClaudeColor.allCases.filter { counts[$0] == least }.randomElement(using: &rng)!
    }

    static func nsColor(_ c: ClaudeColor) -> NSColor {
        switch c {
        case .red: return .systemRed
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .yellow: return .systemYellow
        case .purple: return .systemPurple
        case .orange: return .systemOrange
        case .pink: return .systemPink
        case .cyan: return .systemCyan
        }
    }
}
