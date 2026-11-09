import Foundation
import WorkbenchProtocol

/// What every new surface's shell learns about the workbench, and the window style
/// Ghosttwriter uses in place of the native tab bar.
@MainActor
enum WorkbenchEnvironment {
    static let surfaceKey = "GHOSTTWRITER_SURFACE"
    static let colorKey = "TABCOLOR"
    static let socketKey = "GHOSTTWRITER_SOCKET"

    /// Registers `surface` with the store and sets its id, tab color and control socket in `env`.
    /// A split (`parent` set) gets its tab's color. A `TABCOLOR` already in `env` on a new tab,
    /// as a resumed tab sets it, becomes the surface's color.
    static func apply(
        to env: inout [String: String],
        surface: UUID,
        cwd: String,
        parent: UUID?,
        store: WorkbenchStore
    ) {
        var color = store.surfaceOpened(surface, cwd: cwd, inheritFrom: parent)
        if parent == nil,
           let requested = env[colorKey].flatMap(ClaudeColor.init(rawValue:)),
           requested != color {
            do {
                try store.setColor(surface: surface, requested)
                color = requested
            } catch {
                // The surface was just opened, so this cannot fail; keep the allocated color.
            }
        }
        env[surfaceKey] = surface.uuidString
        env[colorKey] = color.rawValue
        env[socketKey] = SocketPaths.defaultSocket(home: NSHomeDirectory())
    }

    /// The native tab bar is never shown (constraint 4), so the `tabs` titlebar style,
    /// which draws tabs in the titlebar, becomes `transparent`. Other styles are kept.
    nonisolated static func effectiveTitlebarStyle(_ configured: String) -> String {
        configured == "tabs" ? "transparent" : configured
    }
}
