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

    /// Quick-terminal surfaces carry `GHOSTTY_QUICK_TERMINAL` and are not workbench tabs.
    static func isQuickTerminal(_ env: [String: String]) -> Bool {
        env["GHOSTTY_QUICK_TERMINAL"] != nil
    }

    // MARK: Pwd changes

    /// Called with a surface's new pwd. AppDelegate points it at the git status service
    /// so a `cd` refreshes the row at once (constraint 11).
    static var onCwdChange: ((String) -> Void)?

    static func cwdChanged(_ cwd: String) {
        onCwdChange?(cwd)
    }

    // MARK: Tab and split lifecycle

    /// Surfaces that joined `controller`'s split tree. A quick-terminal controller's surfaces
    /// are dropped from the workbench. A surface coming back from an undone close is
    /// registered again with its old color, and its record reattached if still closed.
    static func surfacesAttached(
        _ views: [Ghostty.SurfaceView],
        to controller: BaseTerminalController
    ) {
        let store = WorkbenchStore.shared
        for view in views where view.workbenchTracked {
            if controller is QuickTerminalController {
                view.workbenchTracked = false
                store.surfaceClosed(view.id)
                continue
            }
            guard store.liveSurfaces[view.id] == nil else { continue }
            let cwd = view.pwd.flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
            _ = store.surfaceOpened(view.id, cwd: cwd, inheritFrom: nil)
            if !view.title.isEmpty { store.surfaceChanged(view.id, cwd: nil, title: view.title) }
            if let color = view.workbenchClosedColor {
                try? store.setColor(surface: view.id, color)
            }
            if let rid = view.workbenchClosedRecord,
               let record = store.records[rid], record.closedAt != nil {
                try? store.reattach(record: rid, to: view.id)
            }
            view.workbenchClosedColor = nil
            view.workbenchClosedRecord = nil
        }
    }

    /// Surfaces that left a split tree, or whose tab or window closed. On the next run-loop
    /// turn (after a move into another tab has landed), each one no longer owned by an open
    /// controller has its session record saved and leaves the live set, even though undo
    /// may keep the view alive.
    static func surfacesDetached(_ views: [Ghostty.SurfaceView]) {
        let store = WorkbenchStore.shared
        let tracked = views.filter(\.workbenchTracked)
        guard !tracked.isEmpty else { return }
        DispatchQueue.main.async {
            for view in tracked where view.workbenchTracked {
                if let owner = BaseTerminalController.controller(owning: view),
                   !owner.workbenchWindowClosed {
                    continue
                }
                guard store.liveSurfaces[view.id] != nil else { continue }
                view.workbenchClosedColor = store.color(for: view.id)
                view.workbenchClosedRecord = store.surfaceRecord[view.id]
                store.surfaceClosed(view.id)
            }
        }
    }

    /// The native tab bar is never shown (constraint 4), so the `tabs` titlebar style,
    /// which draws tabs in the titlebar, becomes `transparent`. Other styles are kept.
    nonisolated static func effectiveTitlebarStyle(_ configured: String) -> String {
        configured == "tabs" ? "transparent" : configured
    }
}
