import Foundation

/// Accepts newline-delimited requests on a Unix domain socket and replies
/// with whatever `handler` returns. One request and one reply per connection.
public final class SocketListener: @unchecked Sendable {
    private let path: String
    private let handler: @Sendable (Data) async -> Data
    private let queue = DispatchQueue(label: "gtw.socket.listener")
    private let workers = DispatchQueue(label: "gtw.socket.connection", attributes: .concurrent)
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?

    /// How long a connection may take to send its request.
    static let connectionReadTimeout: TimeInterval = 5

    public init(path: String, handler: @escaping @Sendable (Data) async -> Data) throws {
        _ = try SocketIO.address(path)
        self.path = path
        self.handler = handler
    }

    deinit { stop() }

    public func start() throws {
        try queue.sync {
            guard source == nil else { return }

            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            guard chmod(dir, 0o700) == 0 else { throw POSIXError.current }
            unlink(path)

            let s = socket(AF_UNIX, SOCK_STREAM, 0)
            guard s >= 0 else { throw POSIXError.current }
            var addr = try SocketIO.address(path)
            let bound = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, chmod(path, 0o600) == 0, listen(s, 64) == 0 else {
                let err = POSIXError.current
                close(s)
                unlink(path)
                throw err
            }
            _ = fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK)

            let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: queue)
            src.setEventHandler { [weak self] in self?.acceptPending() }
            src.setCancelHandler { close(s) }
            fd = s
            source = src
            src.resume()
        }
    }

    public func stop() {
        queue.sync {
            guard let src = source else { return }
            source = nil
            fd = -1
            src.cancel()
            unlink(path)
        }
    }

    private func acceptPending() {
        while fd >= 0 {
            let c = accept(fd, nil, nil)
            if c < 0 {
                if errno == EINTR { continue }
                return
            }
            _ = fcntl(c, F_SETFL, fcntl(c, F_GETFL) & ~O_NONBLOCK)
            SocketIO.setNoSigPipe(c)
            SocketIO.setTimeouts(c, Self.connectionReadTimeout)
            let handler = self.handler
            let workers = self.workers
            workers.async { Self.serve(c, handler: handler, workers: workers) }
        }
    }

    private static func serve(
        _ c: Int32,
        handler: @escaping @Sendable (Data) async -> Data,
        workers: DispatchQueue
    ) {
        switch SocketIO.readLine(c, limit: WireCodec.maxRequestBytes + 1) {
        case .failed:
            close(c)
        case .tooLarge:
            let reply = (try? WireCodec.encode(Response.failure("request too large"))) ?? Data()
            _ = SocketIO.writeAll(c, reply)
            shutdown(c, SHUT_WR)
            close(c)
        case .line(let line):
            Task {
                let reply = await handler(line)
                workers.async {
                    _ = SocketIO.writeAll(c, reply)
                    close(c)
                }
            }
        }
    }
}

extension POSIXError {
    static var current: POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
