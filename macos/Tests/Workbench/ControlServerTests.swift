import Foundation
import Testing
import WorkbenchProtocol
@testable import Ghostty

@MainActor
final class FakePresenter: ShowPresenter {
    var calls: [(String, ShowMode, Bool)] = []
    func show(path: String, mode: ShowMode, tty: Bool, surface: UUID) async throws -> ShowResult {
        calls.append((path, mode, tty)); return ShowResult(placed: .pane, png: nil)
    }
}

@MainActor
struct ControlServerTests {
    let dbPath = FileManager.default.temporaryDirectory.appendingPathComponent("cs-\(UUID()).db").path

    func req(_ op: String, _ s: UUID, _ args: [String: JSONValue] = [:], author: Author = .user) -> Request {
        Request(v: 1, op: op, surface: s.uuidString, author: author, args: args)
    }

    @Test func goalOpsRoundTrip() async throws {
        let store = try WorkbenchStore(dbPath: dbPath); let S = UUID()
        _ = store.surfaceOpened(S, cwd: "/r", inheritFrom: nil)
        let srv = ControlServer(store: store, presenter: nil, socketPath: "/dev/null")
        let add = await srv.handle(req("goal.add", S, ["text": .string("ship")], author: .claude))
        #expect(add.ok && add.data?["index"] == .int(1))
        #expect(await srv.handle(req("goal.done", S, ["index": .int(1)])).ok)
        let list = await srv.handle(req("goal.list", S))
        #expect(list.data?["goals"] == .array([.object(["index": .int(1), "text": .string("ship"), "done": .bool(true), "author": .string("claude")])]))
    }

    @Test func hookUpdatesStatus() async throws {
        let store = try WorkbenchStore(dbPath: dbPath); let S = UUID()
        _ = store.surfaceOpened(S, cwd: "/r", inheritFrom: nil)
        let srv = ControlServer(store: store, presenter: nil, socketPath: "/dev/null")
        _ = await srv.handle(req("hook", S, ["event": .string("SessionStart"), "session_id": .string("c1"), "cwd": .string("/r")]))
        _ = await srv.handle(req("hook", S, ["event": .string("UserPromptSubmit"), "session_id": .string("c1"), "cwd": .string("/r")]))
        #expect(try store.record(for: S, create: false)?.status == .working)
        let info = await srv.handle(req("info", S))
        #expect(info.data?["claude_session_id"] == .string("c1") && info.data?["status"] == .string("working"))
    }

    @Test func errorsComeBackAsFailures() async throws {
        let store = try WorkbenchStore(dbPath: dbPath)
        let srv = ControlServer(store: store, presenter: nil, socketPath: "/dev/null")
        let S = UUID()
        #expect(await srv.handle(req("goal.add", S, ["text": .string("x")])) == .failure("unknown surface \(S.uuidString)"))
        #expect(await srv.handle(req("frobnicate", S)) == .failure("unknown op frobnicate"))
        #expect(await srv.handle(Request(v: 1, op: "info", surface: "not-a-uuid", author: .user, args: [:])) == .failure("bad surface not-a-uuid"))
        _ = store.surfaceOpened(S, cwd: "/", inheritFrom: nil)
        #expect(await srv.handle(req("show", S, ["path": .string("/x.html"), "mode": .string("auto"), "tty": .bool(false)])) == .failure("show unavailable"))
        #expect(await srv.handle(req("color.set", S, ["name": .string("mauve")])) == .failure("unknown color mauve"))
    }

    @Test func showDelegatesToPresenter() async throws {
        let store = try WorkbenchStore(dbPath: dbPath); let S = UUID()
        _ = store.surfaceOpened(S, cwd: "/", inheritFrom: nil)
        let p = FakePresenter()
        let srv = ControlServer(store: store, presenter: p, socketPath: "/dev/null")
        let r = await srv.handle(req("show", S, ["path": .string("/a.md"), "mode": .string("pane"), "tty": .bool(false)]))
        #expect(r.data?["placed"] == .string("pane") && p.calls.count == 1)
    }

    @Test func overTheSocket() async throws {
        let store = try WorkbenchStore(dbPath: dbPath); let S = UUID()
        _ = store.surfaceOpened(S, cwd: "/r", inheritFrom: nil)
        let sock = FileManager.default.temporaryDirectory.appendingPathComponent("cs-\(UUID().uuidString.prefix(6))/gtw.sock").path
        let srv = ControlServer(store: store, presenter: nil, socketPath: sock)
        try srv.start(); defer { srv.stop() }
        let resp = try await Task.detached {
            try SocketClient.send(Request(v: 1, op: "note.set", surface: S.uuidString, author: .user, args: ["text": .string("hi")]), socketPath: sock, timeout: 2)
        }.value
        #expect(resp.ok)
        #expect(try store.record(for: S, create: false)?.note == "hi")
    }
}
