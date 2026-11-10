import Foundation
import Testing
@testable import WorkbenchProtocol

struct ProtocolTests {
    @Test func requestRoundTrips() throws {
        let r = Request(v: 1, op: "goal.add", surface: "S1", author: .claude, args: ["text": .string("ship it")])
        let data = try WireCodec.encode(r)
        #expect(data.last == UInt8(ascii: "\n"))
        let back = try WireCodec.decodeRequest(data.dropLast())
        #expect(back == r)
        #expect(back.string("text") == "ship it")
    }

    @Test func everyOpRoundTrips() throws {
        for op in WireOp.allCases {
            let r = Request(v: 1, op: op.rawValue, surface: "S", author: .user, args: [:])
            #expect(try WireCodec.decodeRequest(WireCodec.encode(r).dropLast()) == r)
        }
    }

    @Test func badVersionIsRejected() {
        let line = Data(#"{"v":2,"op":"info","surface":"S","author":"user","args":{}}"#.utf8)
        #expect(throws: ProtocolError.badVersion(2)) { try WireCodec.decodeRequest(line) }
    }

    @Test func oversizeIsRejected() {
        let line = Data(repeating: UInt8(ascii: " "), count: WireCodec.maxRequestBytes + 1)
        #expect(throws: ProtocolError.tooLarge) { try WireCodec.decodeRequest(line) }
    }

    @Test func colorsAreClaudesEight() {
        #expect(ClaudeColor.allCases.map(\.rawValue) == ["red", "blue", "green", "yellow", "purple", "orange", "pink", "cyan"])
        #expect(SessionStatus.needsInput.rawValue == "needs_input")
    }

    @Test func defaultSocketPath() {
        #expect(SocketPaths.defaultSocket(home: "/Users/x") == "/Users/x/Library/Application Support/Ghosttwriter/gtw.sock")
    }
}
