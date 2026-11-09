import Foundation
import Testing
@testable import Ghostty

final class FakeGit: GitRunner, @unchecked Sendable {
    var delay: TimeInterval = 0
    var revParseTimesOut = false
    let lock = NSLock(); var running = 0; var peak = 0
    func run(_ args: [String], cwd: String, timeout: TimeInterval) async throws -> String {
        lock.withLock { running += 1; peak = max(peak, running) }
        defer { lock.withLock { running -= 1 } }
        if args.contains("--show-toplevel") {
            if revParseTimesOut { try await Task.sleep(for: .seconds(timeout)); throw GitRunnerError.timedOut }
            return try cwd.hasPrefix("/repo") ? "/repo\n" : { throw GitRunnerError.failed(128) }()
        }
        if delay > timeout { try await Task.sleep(for: .seconds(timeout)); throw GitRunnerError.timedOut }
        try await Task.sleep(for: .seconds(delay))
        return "# branch.head main\n? x\n"
    }
}

@MainActor
struct GitStatusServiceTests {
    func store() throws -> WorkbenchStore {
        try WorkbenchStore(dbPath: FileManager.default.temporaryDirectory.appendingPathComponent("g-\(UUID()).db").path)
    }

    @Test func resolvesRootAndState() async throws {
        let s = try store(); let svc = GitStatusService(store: s, runner: FakeGit())
        await svc.refresh(cwd: "/repo/sub")
        #expect(s.repoRoots["/repo/sub"] == "/repo" && s.git["/repo"]?.untracked == 1)
    }

    @Test func nonRepoHasNoRoot() async throws {
        let s = try store(); let svc = GitStatusService(store: s, runner: FakeGit())
        await svc.refresh(cwd: "/tmp")
        #expect(s.repoRoots["/tmp"] == nil)
    }

    @Test func timeoutMarksUnknown() async throws {
        let s = try store(); let g = FakeGit(); g.delay = 3
        let svc = GitStatusService(store: s, runner: g, timeout: 0.2)
        await svc.refresh(cwd: "/repo")
        #expect(s.git["/repo"]?.timedOut == true)
    }

    @Test func revParseTimeoutKeepsPreviousRoot() async throws {
        let s = try store(); let g = FakeGit()
        let svc = GitStatusService(store: s, runner: g, timeout: 0.2)
        await svc.refresh(cwd: "/repo/sub")
        #expect(s.repoRoots["/repo/sub"] == "/repo" && s.git["/repo"]?.timedOut == false)
        g.revParseTimesOut = true
        await svc.refresh(cwd: "/repo/sub")
        #expect(s.repoRoots["/repo/sub"] == "/repo")
        #expect(s.git["/repo"]?.timedOut == true && s.git["/repo"]?.branch == "main")
    }

    @Test func atMostFourConcurrent() async throws {
        let s = try store(); let g = FakeGit(); g.delay = 0.1
        let svc = GitStatusService(store: s, runner: g)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 { group.addTask { await svc.refresh(cwd: "/repo/\(i)") } }
        }
        #expect(g.peak <= 4)
    }
}
