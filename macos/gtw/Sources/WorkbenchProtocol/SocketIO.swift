import Foundation

/// Low-level helpers shared by the listener and the client.
enum SocketIO {
    /// Fills a `sockaddr_un` for `path`, or throws ENAMETOOLONG.
    static func address(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return addr
    }

    static func setTimeouts(_ fd: Int32, _ timeout: TimeInterval) {
        let secs = max(timeout, 0.001)
        var tv = timeval(tv_sec: Int(secs), tv_usec: Int32((secs - floor(secs)) * 1_000_000))
        let size = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, size)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, size)
    }

    static func setNoSigPipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    enum ReadResult {
        case line(Data)
        case tooLarge
        case failed(Int32)
    }

    /// Reads until "\n", EOF, or `limit` bytes. Returns the bytes before the newline.
    static func readLine(_ fd: Int32, limit: Int) -> ReadResult {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let want = min(buf.count, limit - data.count)
            if want <= 0 { return .tooLarge }
            let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, want) }
            if n < 0 {
                if errno == EINTR { continue }
                return .failed(errno)
            }
            if n == 0 { return .line(data) }
            if let nl = buf[0..<n].firstIndex(of: UInt8(ascii: "\n")) {
                data.append(contentsOf: buf[0..<nl])
                return .line(data)
            }
            data.append(contentsOf: buf[0..<n])
        }
    }

    /// Writes all of `data`. Returns 0 on success or the failing errno.
    static func writeAll(_ fd: Int32, _ data: Data) -> Int32 {
        data.withUnsafeBytes { raw -> Int32 in
            guard var p = raw.baseAddress else { return 0 }
            var left = raw.count
            while left > 0 {
                let n = write(fd, p, left)
                if n < 0 {
                    if errno == EINTR { continue }
                    return errno
                }
                p += n
                left -= n
            }
            return 0
        }
    }
}
