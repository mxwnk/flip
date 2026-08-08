import Darwin
import Foundation

/// Talks to the running application over its unix socket.
///
/// Sockets rather than distributed notifications, which cannot carry an answer
/// back — and `list` is the command that makes the rest worth having.
public enum ControlClient {
    public enum Failure: Error, CustomStringConvertible {
        case notRunning
        case pathTooLong
        case transport(String)
        case malformedAnswer

        public var description: String {
            switch self {
            case .notRunning:
                return "Flip is not running, or is an older version without the control socket."
            case .pathTooLong:
                return "The socket path is too long for a unix socket."
            case .transport(let detail):
                return detail
            case .malformedAnswer:
                return "Flip answered with something this version does not understand."
            }
        }
    }

    public static func send(_ command: ControlCommand, to path: String = ControlSocket.path) throws -> ControlResponse {
        let handle = try connect(to: path)
        defer { close(handle) }

        var line = try JSONEncoder().encode(command)
        line.append(0x0A)
        try writeAll(line, to: handle)

        // Half-closing tells the other side the request is complete without
        // waiting on a length it would otherwise have to be told.
        shutdown(handle, SHUT_WR)

        let answer = try readAll(from: handle)
        guard let response = try? JSONDecoder().decode(ControlResponse.self, from: answer)
        else { throw Failure.malformedAnswer }

        return response
    }

    private static func connect(to path: String) throws -> Int32 {
        guard path.utf8.count <= ControlSocket.maximumPathLength else { throw Failure.pathTooLong }

        let handle = socket(AF_UNIX, SOCK_STREAM, 0)
        guard handle >= 0 else { throw Failure.transport("could not open a socket") }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { field in
            path.withCString { source in
                strncpy(UnsafeMutableRawPointer(field).assumingMemoryBound(to: CChar.self),
                        source, ControlSocket.maximumPathLength)
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(handle, $0, size) }
        }

        guard connected == 0 else {
            close(handle)
            // Nothing listening and no socket file both mean the same thing to
            // somebody at a prompt: the application is not up.
            throw Failure.notRunning
        }

        return handle
    }

    private static func writeAll(_ data: Data, to handle: Int32) throws {
        var sent = 0
        while sent < data.count {
            let written = data.withUnsafeBytes { buffer in
                Darwin.write(handle, buffer.baseAddress!.advanced(by: sent), data.count - sent)
            }
            guard written > 0 else { throw Failure.transport("the connection closed while writing") }

            sent += written
        }
    }

    private static func readAll(from handle: Int32) throws -> Data {
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)

        while true {
            let read = Darwin.read(handle, &buffer, buffer.count)
            if read == 0 { break }
            guard read > 0 else { throw Failure.transport("the connection closed while reading") }

            collected.append(contentsOf: buffer[0..<read])
        }

        return collected
    }
}
