import Darwin
import Foundation
import FlipControl
import OSLog

/// Answers the `flip` command over a unix socket in Application Support. A
/// blocking accept loop on its own thread, because this must never hold up the
/// event tap. Owner-only permissions are the whole access control.
final class ControlServer: @unchecked Sendable {
    private let log = Logger(subsystem: Bundle.identifier, category: "control")
    private let handle: (ControlCommand) -> ControlResponse

    private var listener: Int32 = -1

    /// The handler is called on the socket thread and must be safe there.
    init(handle: @escaping (ControlCommand) -> ControlResponse) {
        self.handle = handle
    }

    func start() {
        let path = ControlSocket.path
        guard path.utf8.count <= ControlSocket.maximumPathLength else {
            return log.error("the socket path is too long; the flip command will not work")
        }

        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // bind refuses a leftover file; a live one was answered above.
        if isAnswering(at: path) {
            return log.error("another copy is already answering on the control socket")
        }
        unlink(path)

        guard let listener = bind(to: path) else { return }
        self.listener = listener

        let thread = Thread { [weak self] in self?.accept(on: listener) }
        thread.name = "\(Bundle.identifier).control"
        thread.qualityOfService = .utility
        thread.start()

        log.notice("control socket listening")
    }

    func stop() {
        guard listener >= 0 else { return }

        close(listener)
        unlink(ControlSocket.path)
        listener = -1
    }

    /// Separates a stale socket file from a second copy of Flip.
    private func isAnswering(at path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }

        return (try? ControlClient.send(.list, to: path)) != nil
    }

    private func bind(to path: String) -> Int32? {
        let handle = socket(AF_UNIX, SOCK_STREAM, 0)
        guard handle >= 0 else {
            log.error("could not open the control socket")
            return nil
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { field in
            path.withCString { source in
                strncpy(UnsafeMutableRawPointer(field).assumingMemoryBound(to: CChar.self),
                        source, ControlSocket.maximumPathLength)
            }
        }

        // Set before bind, so the socket is never briefly world-writable.
        let previous = umask(0o077)
        defer { umask(previous) }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(handle, $0, size) }
        }

        guard bound == 0, Darwin.listen(handle, 4) == 0 else {
            log.error("could not listen on the control socket: \(String(cString: strerror(errno)), privacy: .public)")
            close(handle)
            return nil
        }

        return handle
    }

    private func accept(on listener: Int32) {
        while true {
            let connection = Darwin.accept(listener, nil, nil)
            guard connection >= 0 else { return }

            serve(connection)
            close(connection)
        }
    }

    private func serve(_ connection: Int32) {
        var request = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)

        // The client half-closes, so reading to the end is the frame.
        while true {
            let read = Darwin.read(connection, &buffer, buffer.count)
            guard read > 0 else { break }

            request.append(contentsOf: buffer[0..<read])
            if request.count > 64 * 1024 { return }
        }

        let response: ControlResponse
        if let command = try? JSONDecoder().decode(ControlCommand.self, from: request) {
            response = handle(command)
        } else {
            response = .failure("could not understand the request")
        }

        guard var answer = try? JSONEncoder().encode(response) else { return }
        answer.append(0x0A)

        _ = answer.withUnsafeBytes { Darwin.write(connection, $0.baseAddress!, answer.count) }
    }
}
