import AppKit
import OSLog
import SwiftUI

/// Replaces Ghostty's close confirmation with the close sheet for active sessions.
@MainActor
enum WorkbenchCloseHook {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jonmoses.ghosttwriter",
        category: "workbench")

    /// Presents the close sheet when the focused surface's session needs a note.
    /// Returns false when the normal close flow should continue instead.
    static func interceptTabClose(window: NSWindow,
                                  focusedSurface: UUID?,
                                  store: WorkbenchStore,
                                  close: @escaping () -> Void) -> Bool {
        guard let surface = focusedSurface,
              let record = try? store.record(for: surface, create: false),
              CloseDecision.shouldPresentSheet(record, scope: .tab) else { return false }

        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled],
            backing: .buffered,
            defer: true)

        /// `.save(nil)` closes without keeping the record.
        enum Outcome { case save(String?), cancel }

        func finish(_ outcome: Outcome) {
            window.endSheet(sheet)
            guard case .save(let note) = outcome else { return }
            do {
                try store.close(surface: surface, note: note)
            } catch {
                logger.error("close sheet could not close the record: \(String(describing: error))")
            }
            close()
        }

        let view = CloseSheet(
            record: record,
            onSave: { finish(.save($0)) },
            onDiscard: { finish(.save(nil)) },
            onCancel: { finish(.cancel) })
        sheet.contentViewController = NSHostingController(rootView: view)
        window.beginSheet(sheet)
        return true
    }
}
