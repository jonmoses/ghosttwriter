import Foundation

/// The eight colors Claude Code uses for its sessions.
public enum ClaudeColor: String, CaseIterable, Codable, Sendable {
    case red, blue, green, yellow, purple, orange, pink, cyan
}

/// Who issued a request: the person at the terminal or Claude.
public enum Author: String, Codable, Sendable {
    case user, claude
}

/// The state of the Claude session running in a surface.
public enum SessionStatus: String, Codable, Sendable {
    case idle, waiting, working
    case needsInput = "needs_input"
}

/// How `show` should present a file.
public enum ShowMode: String, Codable, Sendable {
    case auto, pane, inline
}

/// Where `show` actually placed a file.
public enum ShowPlacement: String, Codable, Sendable {
    case pane, card, tty
}

/// An arbitrary JSON value.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case double(Double)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .bool(let b): try c.encode(b)
        case .double(let d): try c.encode(d)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }
}

/// One request line on the wire.
public struct Request: Codable, Equatable, Sendable {
    public var v: Int
    public var op: String
    public var surface: String
    public var author: Author
    public var args: [String: JSONValue]

    public init(v: Int, op: String, surface: String, author: Author, args: [String: JSONValue]) {
        self.v = v
        self.op = op
        self.surface = surface
        self.author = author
        self.args = args
    }

    public func string(_ key: String) -> String? {
        if case .string(let s) = args[key] { return s }
        return nil
    }

    public func int(_ key: String) -> Int? {
        if case .int(let i) = args[key] { return i }
        return nil
    }

    public func bool(_ key: String) -> Bool? {
        if case .bool(let b) = args[key] { return b }
        return nil
    }
}

/// One response line on the wire.
public struct Response: Codable, Equatable, Sendable {
    public var ok: Bool
    public var data: [String: JSONValue]?
    public var error: String?

    public init(ok: Bool, data: [String: JSONValue]? = nil, error: String? = nil) {
        self.ok = ok
        self.data = data
        self.error = error
    }

    public static func success(_ data: [String: JSONValue] = [:]) -> Response {
        Response(ok: true, data: data, error: nil)
    }

    public static func failure(_ message: String) -> Response {
        Response(ok: false, data: nil, error: message)
    }
}

/// Every operation the control socket understands.
public enum WireOp: String, CaseIterable {
    case hook
    case goalAdd = "goal.add"
    case goalDone = "goal.done"
    case goalUndo = "goal.undo"
    case goalRm = "goal.rm"
    case goalList = "goal.list"
    case noteSet = "note.set"
    case statusSet = "status.set"
    case show
    case colorSet = "color.set"
    case info
}

/// Where the control socket lives.
public enum SocketPaths {
    public static func defaultSocket(home: String) -> String {
        "\(home)/Library/Application Support/Ghosttwriter/gtw.sock"
    }
}
