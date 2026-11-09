import Foundation
import Testing
@testable import GtwCore
import WorkbenchProtocol

struct GtwCoreTests {
    let S = "6F1C0D2E-0000-4000-8000-000000000001"
    func env(_ extra: [String: String] = [:], stdin: String = "", tty: Bool = false) -> GtwEnvironment {
        GtwEnvironment(env: ["GHOSTTWRITER_SURFACE": S, "HOME": "/Users/x"].merging(extra) { $1 }, stdin: Data(stdin.utf8), stdoutIsTTY: tty)
    }

    @Test func goalAddSendsRequestAndPrintsIndex() {
        var sent: Request?
        let out = Gtw.run(["goal", "add", "ship the fix"], env(["CLAUDECODE": "1"])) { r, _ in sent = r; return .success(["index": .int(2)]) }
        #expect(out == GtwOutput(stdout: "2\n", stderr: "", code: 0))
        #expect(sent?.op == "goal.add" && sent?.author == .claude && sent?.surface == S && sent?.string("text") == "ship the fix")
    }

    @Test func authorIsUserWithoutClaudeCode() {
        var sent: Request?
        _ = Gtw.run(["note", "tests left"], env()) { r, _ in sent = r; return .success() }
        #expect(sent?.author == .user && sent?.op == "note.set")
    }

    @Test func goalListFormats() {
        let goals: JSONValue = .array([
            .object(["index": .int(1), "text": .string("find bug"), "done": .bool(true), "author": .string("claude")]),
            .object(["index": .int(2), "text": .string("ship"), "done": .bool(false), "author": .string("user")]),
        ])
        let out = Gtw.run(["goal", "list"], env()) { _, _ in .success(["goals": goals]) }
        #expect(out.stdout == "[x] 1. find bug\n[ ] 2. ship\n" && out.code == 0)
    }

    @Test func exitCodes() {
        #expect(Gtw.run(["goal", "frob"], env()) { _, _ in .success() }.code == 2)
        #expect(Gtw.run(["goal", "done", "x"], env()) { _, _ in .success() }.code == 2)
        let fail = Gtw.run(["goal", "done", "9"], env()) { _, _ in .failure("no goal 9") }
        #expect(fail.code == 1 && fail.stderr == "gtw: no goal 9\n")
        let down = Gtw.run(["info"], env()) { _, _ in throw SocketClientError.unreachable }
        #expect(down.code == 3 && down.stderr == "gtw: Ghosttwriter is not running\n")
        #expect(Gtw.run(["info"], GtwEnvironment(env: [:], stdin: Data(), stdoutIsTTY: false)) { _, _ in .success() }.code == 2)
    }

    @Test func hookForwardsStdin() {
        var sent: Request?; var timeout: TimeInterval = 0
        let json = #"{"session_id":"c1","cwd":"/r","hook_event_name":"SessionStart","source":"clear"}"#
        let out = Gtw.run(["hook"], env(stdin: json)) { r, t in sent = r; timeout = t; return .success() }
        #expect(out == GtwOutput(stdout: "", stderr: "", code: 0))
        #expect(sent?.op == "hook" && sent?.string("event") == "SessionStart" && sent?.string("session_id") == "c1" && sent?.string("source") == "clear")
        #expect(timeout == 0.5)
    }

    @Test func hookIsSilentWhenUnreachable() {
        let json = #"{"session_id":"c1","cwd":"/r","hook_event_name":"Stop"}"#
        #expect(Gtw.run(["hook"], env(stdin: json)) { _, _ in throw SocketClientError.unreachable } == GtwOutput(stdout: "", stderr: "", code: 0))
        #expect(Gtw.run(["hook"], env(stdin: json)) { _, _ in .failure("unknown surface x") } == GtwOutput(stdout: "", stderr: "", code: 0))
        #expect(Gtw.run(["hook"], env(stdin: "not json")) { _, _ in .success() }.code == 0)
        let noSurface = GtwEnvironment(env: [:], stdin: Data(json.utf8), stdoutIsTTY: false)
        #expect(Gtw.run(["hook"], noSurface) { _, _ in .success() }.code == 0)
    }

    @Test func hookTruncatesStdinAt64KB() {
        var called = false
        let big = String(repeating: "x", count: 70_000)
        _ = Gtw.run(["hook"], env(stdin: big)) { _, _ in called = true; return .success() }
        #expect(called == false)
    }

    @Test func showWritesKittyOnlyOnTTY() throws {
        let png = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID()).png")
        try Data([0x89]).write(to: png)
        let onTTY = Gtw.run(["show", "/a.html"], env(tty: true)) { r, _ in
            #expect(r.bool("tty") == true && r.string("mode") == "auto")
            return .success(["placed": .string("tty"), "png": .string(png.path)])
        }
        #expect(onTTY.stdout == KittyImage.escape(forPNGAt: png.path) + "\n")
        #expect(!FileManager.default.fileExists(atPath: png.path))
        let piped = Gtw.run(["show", "/a.html", "--pane"], env()) { r, _ in
            #expect(r.bool("tty") == false && r.string("mode") == "pane")
            return .success(["placed": .string("pane")])
        }
        #expect(piped.stdout == "opened in side pane\n")
    }

    @Test func kittyEscape() {
        let b64 = Data("/tmp/a.png".utf8).base64EncodedString()
        #expect(KittyImage.escape(forPNGAt: "/tmp/a.png") == "\u{1b}_Ga=T,f=100,t=f;\(b64)\u{1b}\\")
    }

    @Test func statusDoneAndClearSendFlag() {
        var sent: Request?
        _ = Gtw.run(["status", "done"], env()) { r, _ in sent = r; return .success() }
        #expect(sent?.op == "status.set" && sent?.bool("done") == true)
        _ = Gtw.run(["status", "clear"], env()) { r, _ in sent = r; return .success() }
        #expect(sent?.bool("done") == false)
        #expect(Gtw.run(["status", "maybe"], env()) { _, _ in .success() }.code == 2)
    }

    @Test func colorPrintsSlashCommand() {
        let out = Gtw.run(["color", "pink"], env()) { _, _ in .success() }
        #expect(out.stdout == "/color pink\n")
    }
}
