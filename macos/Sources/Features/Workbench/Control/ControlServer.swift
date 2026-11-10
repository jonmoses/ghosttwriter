import Foundation
import WorkbenchProtocol

/// Serves `gtw` requests on the control socket and dispatches them to the `WorkbenchStore`.
@MainActor
final class ControlServer {
    /// How long `show` may take before the reply is a timeout failure.
    static let showTimeout: Duration = .seconds(5)

    private let store: WorkbenchStore
    private let presenter: ShowPresenter?
    private let socketPath: String
    private var listener: SocketListener?

    init(store: WorkbenchStore, presenter: ShowPresenter?, socketPath: String) {
        self.store = store
        self.presenter = presenter
        self.socketPath = socketPath
    }

    /// Starts listening on `socketPath`. Calling it again while running does nothing.
    func start() throws {
        guard listener == nil else { return }
        let l = try SocketListener(path: socketPath) { [weak self] line in
            let request: Request
            do {
                request = try WireCodec.decodeRequest(line)
            } catch let error as ProtocolError {
                return Self.encode(.failure("bad request: \(Self.describe(error))"))
            } catch {
                return Self.encode(.failure("bad request: \(error)"))
            }
            guard let self else { return Self.encode(.failure("server stopped")) }
            return Self.encode(await self.handle(request))
        }
        try l.start()
        listener = l
    }

    func stop() {
        listener?.stop()
        listener = nil
    }

    /// Runs one request against the store and returns its reply.
    func handle(_ request: Request) async -> Response {
        guard let surface = UUID(uuidString: request.surface) else {
            return .failure("bad surface \(request.surface)")
        }
        guard let op = WireOp(rawValue: request.op) else {
            return .failure("unknown op \(request.op)")
        }
        do {
            if op == .show { return try await show(surface, request) }
            return try dispatch(op, surface, request)
        } catch let error as WorkbenchError {
            return .failure(error.description)
        } catch let error as ArgumentError {
            return .failure(error.description)
        } catch {
            return .failure(String(describing: error))
        }
    }

    // MARK: Dispatch

    private func dispatch(_ op: WireOp, _ surface: UUID, _ r: Request) throws -> Response {
        switch op {
        case .hook:
            let event = HookEvent(
                name: try Self.string(r, "event"),
                sessionId: try Self.string(r, "session_id"),
                cwd: r.string("cwd") ?? "",
                source: r.string("source"),
                message: r.string("message"))
            try store.handleHook(surface: surface, event: event)
            return .success()

        case .goalAdd:
            _ = try store.record(for: surface, create: true)
            let index = try store.addGoal(surface: surface, text: try Self.string(r, "text"), author: r.author)
            return .success(["index": .int(index)])

        case .goalDone, .goalUndo:
            _ = try store.record(for: surface, create: true)
            try store.setGoal(surface: surface, index: try Self.int(r, "index"), done: op == .goalDone, author: r.author)
            return .success()

        case .goalRm:
            _ = try store.record(for: surface, create: true)
            try store.removeGoal(surface: surface, index: try Self.int(r, "index"), author: r.author)
            return .success()

        case .goalList:
            let record = try store.record(for: surface, create: true)
            let goals: [JSONValue] = (record?.goals ?? []).enumerated().map { i, g in
                .object([
                    "index": .int(i + 1),
                    "text": .string(g.text),
                    "done": .bool(g.done),
                    "author": .string(g.author.rawValue),
                ])
            }
            return .success(["goals": .array(goals)])

        case .noteSet:
            _ = try store.record(for: surface, create: true)
            try store.setNote(surface: surface, text: try Self.string(r, "text"), author: r.author)
            return .success()

        case .statusSet:
            _ = try store.record(for: surface, create: true)
            try store.setManualDone(surface: surface, try Self.bool(r, "done"))
            return .success()

        case .colorSet:
            let name = try Self.string(r, "name")
            guard let color = ClaudeColor(rawValue: name) else { throw WorkbenchError.unknownColor(name) }
            try store.setColor(surface: surface, color)
            return .success()

        case .info:
            return .success(try info(surface))

        case .show:
            // Handled asynchronously in `handle`.
            return .failure("show unavailable")
        }
    }

    private func info(_ surface: UUID) throws -> [String: JSONValue] {
        let live = store.liveSurfaces[surface]
        let record = try store.record(for: surface, create: false)
        guard live != nil || record != nil else { throw WorkbenchError.unknownSurface(surface) }

        var data: [String: JSONValue] = ["surface": .string(surface.uuidString)]
        if let record {
            data["record_id"] = .string(record.id.uuidString)
            if let sid = record.claudeSessionId { data["claude_session_id"] = .string(sid) }
            data["status"] = .string(record.status.rawValue)
            data["color"] = .string(record.color.rawValue)
            data["cwd"] = .string(record.cwd)
        } else if let live {
            data["status"] = .string(SessionStatus.idle.rawValue)
            data["color"] = .string(live.color.rawValue)
            data["cwd"] = .string(live.cwd)
        }
        return data
    }

    // MARK: Show

    private func show(_ surface: UUID, _ r: Request) async throws -> Response {
        guard let presenter else { throw WorkbenchError.unavailable("show") }
        guard store.liveSurfaces[surface] != nil else { throw WorkbenchError.unknownSurface(surface) }
        let path = try Self.string(r, "path")
        let modeName = r.string("mode") ?? ShowMode.auto.rawValue
        guard let mode = ShowMode(rawValue: modeName) else { throw ArgumentError.invalid("mode", modeName) }
        let tty = r.bool("tty") ?? false

        // Race the presenter against the timeout. The first reply wins, so a
        // presenter that ignores cancellation cannot hold the reply past the limit.
        let (replies, continuation) = AsyncStream.makeStream(of: Response.self)
        let work = Task { @MainActor in
            let reply: Response
            do {
                let result = try await presenter.show(path: path, mode: mode, tty: tty, surface: surface)
                var data: [String: JSONValue] = ["placed": .string(result.placed.rawValue)]
                if let png = result.png { data["png"] = .string(png) }
                reply = .success(data)
            } catch let error as WorkbenchError {
                reply = .failure(error.description)
            } catch {
                reply = .failure("show failed: \(error.localizedDescription)")
            }
            continuation.yield(reply)
            continuation.finish()
        }
        let timer = Task {
            try? await Task.sleep(for: Self.showTimeout)
            continuation.yield(.failure("show timed out"))
            continuation.finish()
        }
        var iterator = replies.makeAsyncIterator()
        let reply = await iterator.next() ?? .failure("show timed out")
        work.cancel()
        timer.cancel()
        return reply
    }

    // MARK: Arguments

    private enum ArgumentError: Error, CustomStringConvertible {
        case missing(String)
        case invalid(String, String)

        var description: String {
            switch self {
            case .missing(let key): return "missing argument \(key)"
            case .invalid(let key, let value): return "bad \(key) \(value)"
            }
        }
    }

    private static func string(_ r: Request, _ key: String) throws -> String {
        guard let v = r.string(key) else { throw ArgumentError.missing(key) }
        return v
    }

    private static func int(_ r: Request, _ key: String) throws -> Int {
        guard let v = r.int(key) else { throw ArgumentError.missing(key) }
        return v
    }

    private static func bool(_ r: Request, _ key: String) throws -> Bool {
        guard let v = r.bool(key) else { throw ArgumentError.missing(key) }
        return v
    }

    // MARK: Wire

    private nonisolated static func encode(_ response: Response) -> Data {
        (try? WireCodec.encode(response)) ?? Data("{\"error\":\"encode failed\",\"ok\":false}\n".utf8)
    }

    private nonisolated static func describe(_ error: ProtocolError) -> String {
        switch error {
        case .tooLarge: return "request too large"
        case .badVersion(let v): return "unsupported version \(v)"
        case .malformed(let detail): return detail
        }
    }
}
