import Foundation
import Testing
@testable import WorkbenchProtocol

struct SocketTests {
    func tempSocket() -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gtw-\(UUID().uuidString.prefix(8))")
        return dir.appendingPathComponent("gtw.sock").path
    }

    @Test func roundTripAndModes() throws {
        let path = tempSocket()
        let l = try SocketListener(path: path) { line in
            let req = try! WireCodec.decodeRequest(line)
            return try! WireCodec.encode(Response.success(["op": .string(req.op)]))
        }
        try l.start(); defer { l.stop() }
        let resp = try SocketClient.send(Request(v: 1, op: "info", surface: "S", author: .user, args: [:]), socketPath: path, timeout: 1)
        #expect(resp.ok && resp.data?["op"] == .string("info"))
        let sockMode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        let dirMode = try FileManager.default.attributesOfItem(atPath: (path as NSString).deletingLastPathComponent)[.posixPermissions] as? Int
        #expect(sockMode == 0o600 && dirMode == 0o700)
    }

    @Test func oversizeGetsFailureReply() throws {
        let path = tempSocket()
        let l = try SocketListener(path: path) { _ in try! WireCodec.encode(Response.success()) }
        try l.start(); defer { l.stop() }
        let big = Request(v: 1, op: "note.set", surface: "S", author: .user,
                          args: ["text": .string(String(repeating: "x", count: WireCodec.maxRequestBytes))])
        let resp = try SocketClient.send(big, socketPath: path, timeout: 2)
        #expect(resp.ok == false && resp.error == "request too large")
    }

    @Test func secondListenerDoesNotStealLiveSocket() throws {
        let path = tempSocket()
        let first = try SocketListener(path: path) { _ in try! WireCodec.encode(Response.success(["who": .string("first")])) }
        try first.start(); defer { first.stop() }
        let second = try SocketListener(path: path) { _ in try! WireCodec.encode(Response.success(["who": .string("second")])) }
        #expect(throws: POSIXError(.EADDRINUSE)) { try second.start() }
        second.stop()
        let resp = try SocketClient.send(Request(v: 1, op: "info", surface: "S", author: .user, args: [:]), socketPath: path, timeout: 1)
        #expect(resp.data?["who"] == .string("first"))
    }

    @Test func staleSocketFileIsReplaced() throws {
        let path = tempSocket()
        let first = try SocketListener(path: path) { _ in try! WireCodec.encode(Response.success()) }
        try first.start()
        // Leave a socket file nobody listens on, as a crash would.
        let dir = (path as NSString).deletingLastPathComponent
        let s = socket(AF_UNIX, SOCK_STREAM, 0); defer { close(s) }
        first.stop()
        var addr = try SocketIO.address(path)
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        #expect(FileManager.default.fileExists(atPath: path) && FileManager.default.fileExists(atPath: dir))
        let second = try SocketListener(path: path) { _ in try! WireCodec.encode(Response.success()) }
        try second.start(); defer { second.stop() }
        let resp = try SocketClient.send(Request(v: 1, op: "info", surface: "S", author: .user, args: [:]), socketPath: path, timeout: 1)
        #expect(resp.ok)
    }

    @Test func unreachableSocketThrows() {
        #expect(throws: SocketClientError.unreachable) {
            try SocketClient.send(Request(v: 1, op: "info", surface: "S", author: .user, args: [:]), socketPath: "/tmp/nope-\(UUID()).sock", timeout: 0.5)
        }
    }
}
