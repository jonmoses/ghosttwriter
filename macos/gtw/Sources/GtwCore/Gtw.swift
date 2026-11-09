import Foundation
import WorkbenchProtocol

/// Everything `gtw` reads from its process.
public struct GtwEnvironment {
    public var env: [String: String]
    public var stdin: Data
    public var stdoutIsTTY: Bool

    public init(env: [String: String], stdin: Data, stdoutIsTTY: Bool) {
        self.env = env
        self.stdin = stdin
        self.stdoutIsTTY = stdoutIsTTY
    }
}

/// Everything `gtw` writes before it exits.
public struct GtwOutput: Equatable {
    public var stdout: String
    public var stderr: String
    public var code: Int32

    public init(stdout: String, stderr: String, code: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.code = code
    }
}

/// The `gtw` command line (spec 6.2), independent of the process and socket.
public enum Gtw {
    /// `gtw hook` forwards nothing when stdin is larger than this.
    public static let maxHookInputBytes = 65_536

    static let hookTimeout: TimeInterval = 0.5
    static let requestTimeout: TimeInterval = 5.0
    static let showTimeout: TimeInterval = 7.0

    static let usage = """
        usage: gtw [--surface <uuid>] [--socket <path>] <command>
          goal add "<text>" | goal done <n> | goal undo <n> | goal rm <n> | goal list [--json]
          note "<text>" | status done|clear | show <file> [--pane|--inline]
          color <name> | hook | info [--json]
        """

    public static func run(
        _ args: [String],
        _ environment: GtwEnvironment,
        send: (Request, TimeInterval) throws -> Response
    ) -> GtwOutput {
        let parsed = parseGlobals(args)

        if parsed.rest.first == "hook" {
            hook(surface: surface(parsed.surface, environment), environment, send: send)
            return GtwOutput(stdout: "", stderr: "", code: 0)
        }
        if let flagError = parsed.error { return usageError(flagError) }

        let command: Command
        switch parse(parsed.rest) {
        case .failure(let error): return usageError(error.message)
        case .success(let c): command = c
        }

        guard let surface = surface(parsed.surface, environment) else {
            return GtwOutput(stdout: "", stderr: "gtw: not inside a Ghosttwriter surface\n", code: 2)
        }

        var args = command.args
        if command.op == .show {
            args["tty"] = .bool(environment.stdoutIsTTY)
        }
        let request = Request(
            v: WireCodec.protocolVersion,
            op: command.op.rawValue,
            surface: surface,
            author: environment.env["CLAUDECODE"] == "1" ? .claude : .user,
            args: args)

        let response: Response
        do {
            response = try send(request, command.op == .show ? showTimeout : requestTimeout)
        } catch {
            return GtwOutput(stdout: "", stderr: "gtw: Ghosttwriter is not running\n", code: 3)
        }
        guard response.ok else {
            return GtwOutput(stdout: "", stderr: "gtw: \(response.error ?? "request failed")\n", code: 1)
        }
        return command.render(response.data ?? [:])
    }

    /// The command name after the global flags, if any.
    public static func command(_ args: [String]) -> String? {
        parseGlobals(args).rest.first
    }

    /// The `--socket` path, else `GHOSTTWRITER_SOCKET`, else nil.
    public static func socketPath(_ args: [String], env: [String: String]) -> String? {
        if let flag = parseGlobals(args).socket, !flag.isEmpty { return flag }
        if let path = env["GHOSTTWRITER_SOCKET"], !path.isEmpty { return path }
        return nil
    }

    // MARK: Global flags

    struct Globals {
        var surface: String?
        var socket: String?
        var rest: [String] = []
        var error: String?
    }

    static func parseGlobals(_ args: [String]) -> Globals {
        var g = Globals()
        var i = 0
        while i < args.count {
            let a = args[i]
            var name: String?
            var value: String?
            if a == "--surface" || a == "--socket" {
                name = a
                if i + 1 < args.count {
                    value = args[i + 1]
                    i += 1
                } else {
                    g.error = "\(a) needs a value"
                }
            } else if a.hasPrefix("--surface=") || a.hasPrefix("--socket=") {
                let parts = a.split(separator: "=", maxSplits: 1)
                name = String(parts[0])
                value = parts.count > 1 ? String(parts[1]) : ""
            }
            if let name {
                if name == "--surface" { g.surface = value } else { g.socket = value }
            } else {
                g.rest.append(a)
            }
            i += 1
        }
        return g
    }

    static func surface(_ flag: String?, _ environment: GtwEnvironment) -> String? {
        if let flag, !flag.isEmpty { return flag }
        if let env = environment.env["GHOSTTWRITER_SURFACE"], !env.isEmpty { return env }
        return nil
    }

    static func usageError(_ message: String) -> GtwOutput {
        GtwOutput(stdout: "", stderr: "gtw: \(message)\n\(usage)\n", code: 2)
    }

    // MARK: hook

    /// Forwards one Claude hook payload. Every failure is silent.
    static func hook(
        surface: String?,
        _ environment: GtwEnvironment,
        send: (Request, TimeInterval) throws -> Response
    ) {
        guard let surface,
              environment.stdin.count <= maxHookInputBytes,
              let object = try? JSONSerialization.jsonObject(with: environment.stdin) as? [String: Any],
              let event = object["hook_event_name"] as? String
        else { return }

        var args: [String: JSONValue] = ["event": .string(event)]
        for (key, name) in [("session_id", "session_id"), ("cwd", "cwd"), ("source", "source"), ("message", "message")] {
            if let value = object[key] as? String { args[name] = .string(value) }
        }
        let request = Request(
            v: WireCodec.protocolVersion,
            op: WireOp.hook.rawValue,
            surface: surface,
            author: environment.env["CLAUDECODE"] == "1" ? .claude : .user,
            args: args)
        _ = try? send(request, hookTimeout)
    }

    // MARK: Commands

    struct UsageError: Error {
        var message: String
    }

    struct Command {
        var op: WireOp
        var args: [String: JSONValue] = [:]
        var render: ([String: JSONValue]) -> GtwOutput = { _ in ok("") }
    }

    static func ok(_ stdout: String) -> GtwOutput {
        GtwOutput(stdout: stdout, stderr: "", code: 0)
    }

    static func parse(_ argv: [String]) -> Result<Command, UsageError> {
        guard let name = argv.first else { return .failure(UsageError(message: "missing command")) }
        let rest = Array(argv.dropFirst())
        switch name {
        case "goal": return parseGoal(rest)
        case "note":
            guard !rest.isEmpty else { return .failure(UsageError(message: "note needs text (\"\" clears it)")) }
            return .success(Command(op: .noteSet, args: ["text": .string(rest.joined(separator: " "))]))
        case "status":
            guard rest.count == 1, rest[0] == "done" || rest[0] == "clear" else {
                return .failure(UsageError(message: "status takes done or clear"))
            }
            return .success(Command(op: .statusSet, args: ["done": .bool(rest[0] == "done")]))
        case "show": return parseShow(rest)
        case "color":
            guard rest.count == 1, !rest[0].isEmpty else { return .failure(UsageError(message: "color takes one name")) }
            let color = rest[0]
            return .success(Command(op: .colorSet, args: ["name": .string(color)]) { _ in ok("/color \(color)\n") })
        case "info":
            guard let json = jsonFlag(rest) else { return .failure(UsageError(message: "info takes only --json")) }
            return .success(Command(op: .info) { data in json ? ok(encodeJSON(.object(data))) : ok(formatInfo(data)) })
        default:
            return .failure(UsageError(message: "unknown command \(name)"))
        }
    }

    static func parseGoal(_ argv: [String]) -> Result<Command, UsageError> {
        guard let sub = argv.first else { return .failure(UsageError(message: "goal needs a subcommand")) }
        let rest = Array(argv.dropFirst())
        switch sub {
        case "add":
            let text = rest.joined(separator: " ")
            guard !text.isEmpty else { return .failure(UsageError(message: "goal add needs text")) }
            return .success(Command(op: .goalAdd, args: ["text": .string(text)]) { data in
                if case .int(let index) = data["index"] { return ok("\(index)\n") }
                return ok("")
            })
        case "done", "undo", "rm":
            guard rest.count == 1, let index = Int(rest[0]), index >= 1 else {
                return .failure(UsageError(message: "goal \(sub) takes one goal number"))
            }
            let op: WireOp = sub == "done" ? .goalDone : sub == "undo" ? .goalUndo : .goalRm
            return .success(Command(op: op, args: ["index": .int(index)]))
        case "list":
            guard let json = jsonFlag(rest) else { return .failure(UsageError(message: "goal list takes only --json")) }
            return .success(Command(op: .goalList) { data in
                let goals = data["goals"] ?? .array([])
                return json ? ok(encodeJSON(goals)) : ok(formatGoals(goals))
            })
        default:
            return .failure(UsageError(message: "unknown goal subcommand \(sub)"))
        }
    }

    static func parseShow(_ argv: [String]) -> Result<Command, UsageError> {
        var mode = ShowMode.auto
        var file: String?
        for a in argv {
            switch a {
            case "--pane", "--inline":
                guard mode == .auto else { return .failure(UsageError(message: "use only one of --pane and --inline")) }
                mode = a == "--pane" ? .pane : .inline
            default:
                guard file == nil, !a.isEmpty else { return .failure(UsageError(message: "show takes one file")) }
                file = a
            }
        }
        guard let file else { return .failure(UsageError(message: "show needs a file")) }
        let cwd = FileManager.default.currentDirectoryPath
        let path = URL(fileURLWithPath: file, relativeTo: URL(fileURLWithPath: cwd, isDirectory: true))
            .standardizedFileURL.path
        return .success(Command(op: .show, args: ["path": .string(path), "mode": .string(mode.rawValue)]) { data in
            guard case .string(let placedName) = data["placed"], let placed = ShowPlacement(rawValue: placedName) else {
                return GtwOutput(stdout: "", stderr: "gtw: unexpected reply to show\n", code: 1)
            }
            switch placed {
            case .pane: return ok("opened in side pane\n")
            case .card: return ok("shown as inline card\n")
            case .tty:
                guard case .string(let png) = data["png"] else {
                    return GtwOutput(stdout: "", stderr: "gtw: show returned no image\n", code: 1)
                }
                let escape = KittyImage.escape(forPNGAt: png)
                try? FileManager.default.removeItem(atPath: png)
                return ok(escape + "\n")
            }
        })
    }

    /// nil when `argv` holds anything other than an optional `--json`.
    static func jsonFlag(_ argv: [String]) -> Bool? {
        if argv.isEmpty { return false }
        if argv == ["--json"] { return true }
        return nil
    }

    // MARK: Formatting

    static func formatGoals(_ goals: JSONValue) -> String {
        guard case .array(let items) = goals else { return "" }
        var out = ""
        for item in items {
            guard case .object(let g) = item else { continue }
            let done = g["done"] == .bool(true)
            let index: String
            if case .int(let i) = g["index"] { index = String(i) } else { index = "?" }
            var text = ""
            if case .string(let t) = g["text"] { text = t }
            out += "[\(done ? "x" : " ")] \(index). \(text)\n"
        }
        return out
    }

    static func formatInfo(_ data: [String: JSONValue]) -> String {
        var out = ""
        for key in ["surface", "record_id", "claude_session_id", "status", "color", "cwd"] {
            if case .string(let value) = data[key] { out += "\(key): \(value)\n" }
        }
        return out
    }

    static func encodeJSON(_ value: JSONValue) -> String {
        guard let data = try? WireCodec.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
