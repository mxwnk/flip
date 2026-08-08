import Foundation

/// What the `flip` command and the running application say to each other.
///
/// Shared by both rather than written twice: the wire format is the one thing
/// that cannot drift, because the two halves ship together but are built as
/// separate binaries and could easily be updated apart.
///
/// One JSON object per line, one line each way, then the connection closes.
/// Nothing here streams, and no command takes long enough to want it to.
public enum ControlCommand: Codable, Sendable {
    case list
    case focus(UInt32)
    case arrange(String)
    case switcher
    case pause
    case resume

    public var isPause: Bool {
        if case .pause = self { return true }
        return false
    }
}

public struct ControlWindow: Codable, Sendable {
    public let id: UInt32
    public let app: String
    public let title: String
    public let minimized: Bool

    public init(id: UInt32, app: String, title: String, minimized: Bool) {
        self.id = id
        self.app = app
        self.title = title
        self.minimized = minimized
    }
}

public enum ControlResponse: Codable, Sendable {
    case windows([ControlWindow])
    case ok
    case failure(String)
}

/// The names `flip arrange` takes, and the only place they are written down.
/// The application maps them onto its own arrangements; the command validates
/// against them so a typo is answered locally instead of over the socket.
public enum ControlArrangement {
    public static let names = [
        "left-half", "right-half", "top-half", "bottom-half",
        "top-left", "top-right", "bottom-left", "bottom-right",
        "fill", "previous-display", "next-display",
    ]
}

public enum ControlSocket {
    /// Beside the two configuration files, because it belongs to this user and
    /// this login session and nothing else should be able to reach it.
    public static var path: String {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flip", isDirectory: true)

        return support.appendingPathComponent("control.sock").path
    }

    /// A socket path is copied into a fixed-size C buffer, so a long one is
    /// truncated rather than rejected — which fails much later and confusingly.
    public static let maximumPathLength = 103
}
