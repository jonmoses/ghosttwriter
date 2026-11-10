import Foundation
import Testing
@testable import Ghostty

/// Other @MainActor suites (TabGroupBridgeTests builds tabbed NSWindows) run in parallel and can
/// hold the main thread for a second or more, which only delays FileWatcher's callback. So these
/// tests wait for a deadline instead of checking at fixed sleeps, and check the debounce by when
/// the callback fired.
@MainActor
struct FileWatcherTests {
    func tempFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fw-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("page.html"); try "a".write(to: f, atomically: false, encoding: .utf8); return f
    }

    /// Polls `condition` on the main actor until it holds or `timeout` passes.
    func waitUntil(_ timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline { return false }
            try await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    @Test func inPlaceWriteTriggersOnceAfterDebounce() async throws {
        let f = try tempFile(); var n = 0; var firedAt: ContinuousClock.Instant?
        let w = FileWatcher(url: f, debounce: 0.15) { n += 1; firedAt = .now }; w.start(); defer { w.stop() }
        for i in 0..<5 { try "b\(i)".write(to: f, atomically: false, encoding: .utf8) }
        let lastWrite = ContinuousClock.now
        #expect(try await waitUntil { n >= 1 })
        let fired = try #require(firedAt)
        #expect(fired - lastWrite >= .milliseconds(150))
        try await Task.sleep(for: .milliseconds(400))
        #expect(n == 1)
    }

    @Test func atomicRenameTriggersChange() async throws {
        let f = try tempFile(); var n = 0
        let w = FileWatcher(url: f, debounce: 0.05) { n += 1 }; w.start(); defer { w.stop() }
        try "new".write(to: f, atomically: true, encoding: .utf8)
        #expect(try await waitUntil { n >= 1 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(n == 1)
        try "newer".write(to: f, atomically: true, encoding: .utf8)
        #expect(try await waitUntil { n >= 2 })
        try await Task.sleep(for: .milliseconds(200))
        #expect(n == 2)
    }
}
