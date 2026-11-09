import Foundation

public enum SocketClientError: Error {
    case unreachable, timedOut, badReply
}

/// Sends one request over the control socket and waits for its reply.
public enum SocketClient {
    public static func send(_ request: Request, socketPath: String, timeout: TimeInterval) throws -> Response {
        let payload: Data
        do { payload = try WireCodec.encode(request) } catch { throw SocketClientError.badReply }

        guard var addr = try? SocketIO.address(socketPath) else { throw SocketClientError.unreachable }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketClientError.unreachable }
        defer { close(fd) }
        SocketIO.setNoSigPipe(fd)
        SocketIO.setTimeouts(fd, timeout)

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            if errno == ETIMEDOUT { throw SocketClientError.timedOut }
            throw SocketClientError.unreachable
        }

        // A write error (e.g. EPIPE after the server rejected an oversize
        // request) still leaves the server's reply readable.
        let writeErr = SocketIO.writeAll(fd, payload)
        if isTimeout(writeErr) { throw SocketClientError.timedOut }

        switch SocketIO.readLine(fd, limit: WireCodec.maxRequestBytes + 1) {
        case .failed(let err):
            if isTimeout(err) { throw SocketClientError.timedOut }
            throw SocketClientError.badReply
        case .tooLarge:
            throw SocketClientError.badReply
        case .line(let line):
            guard !line.isEmpty, let response = try? WireCodec.decodeResponse(line) else {
                throw SocketClientError.badReply
            }
            return response
        }
    }

    private static func isTimeout(_ err: Int32) -> Bool {
        err == EAGAIN || err == EWOULDBLOCK || err == ETIMEDOUT
    }
}
