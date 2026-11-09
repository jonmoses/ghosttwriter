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

    @Test func unreachableSocketThrows() {
        #expect(throws: SocketClientError.unreachable) {
            try SocketClient.send(Request(v: 1, op: "info", surface: "S", author: .user, args: [:]), socketPath: "/tmp/nope-\(UUID()).sock", timeout: 0.5)
        }
    }
}
