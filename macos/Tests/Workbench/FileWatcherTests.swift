import Foundation
import Testing
@testable import Ghostty

@MainActor
struct FileWatcherTests {
    func tempFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fw-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("page.html"); try "a".write(to: f, atomically: false, encoding: .utf8); return f
    }

    @Test func inPlaceWriteTriggersOnceAfterDebounce() async throws {
        let f = try tempFile(); var n = 0
        let w = FileWatcher(url: f, debounce: 0.15) { n += 1 }; w.start(); defer { w.stop() }
        for i in 0..<5 { try "b\(i)".write(to: f, atomically: false, encoding: .utf8) }
        try await Task.sleep(for: .milliseconds(100)); #expect(n == 0)
        try await Task.sleep(for: .milliseconds(300)); #expect(n == 1)
    }

    @Test func atomicRenameTriggersChange() async throws {
        let f = try tempFile(); var n = 0
        let w = FileWatcher(url: f, debounce: 0.05) { n += 1 }; w.start(); defer { w.stop() }
        try "new".write(to: f, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(300)); #expect(n == 1)
        try "newer".write(to: f, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(300)); #expect(n == 2)
    }
}
