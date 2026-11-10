import Foundation

public enum ProtocolError: Error, Equatable {
    case badVersion(Int)
    case tooLarge
    case malformed(String)
}

/// Newline-delimited JSON framing for the control socket.
public enum WireCodec {
    public static let protocolVersion = 1
    public static let maxRequestBytes = 1_048_576

    /// Encodes `value` as one JSON line, terminated by "\n".
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// Decodes one request line (without its trailing newline).
    public static func decodeRequest(_ line: Data) throws -> Request {
        if line.count > maxRequestBytes { throw ProtocolError.tooLarge }
        let request: Request
        do {
            request = try JSONDecoder().decode(Request.self, from: line)
        } catch {
            throw ProtocolError.malformed(String(describing: error))
        }
        guard request.v == protocolVersion else { throw ProtocolError.badVersion(request.v) }
        return request
    }

    /// Decodes one response line (without its trailing newline).
    public static func decodeResponse(_ line: Data) throws -> Response {
        do {
            return try JSONDecoder().decode(Response.self, from: line)
        } catch {
            throw ProtocolError.malformed(String(describing: error))
        }
    }
}
