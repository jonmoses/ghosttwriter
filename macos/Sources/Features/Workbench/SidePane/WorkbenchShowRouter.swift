import CoreGraphics
import Foundation
import WorkbenchProtocol

/// Presents `gtw show` requests: in the tab's side pane, as an inline snapshot card,
/// or as a PNG for gtw to draw in the terminal.
@MainActor
final class WorkbenchShowRouter: ShowPresenter {
    private let registry: SidePaneRegistry
    private let renderer: SnapshotRenderer
    private let terminalWidth: @MainActor (UUID) -> CGFloat?

    init(
        registry: SidePaneRegistry = .shared,
        renderer: SnapshotRenderer = SnapshotRenderer(),
        terminalWidth: @escaping @MainActor (UUID) -> CGFloat?
    ) {
        self.registry = registry
        self.renderer = renderer
        self.terminalWidth = terminalWidth
    }

    func show(path: String, mode: ShowMode, tty: Bool, surface: UUID) async throws -> ShowResult {
        guard let model = registry.model(for: surface) else { throw WorkbenchError.unavailable("side pane") }
        let url = URL(fileURLWithPath: path)
        switch try ShowRouting.preflight(path: path, mode: mode) {
        case .unsupported:
            throw WorkbenchError.unavailable("preview for this file type")
        case .pane:
            model.open(url)
            return ShowResult(placed: .pane)
        case .render:
            let width = ShowRouting.renderWidth(terminalWidth: terminalWidth(surface) ?? 800)
            let snap = try await renderer.render(url: url, width: width)
            switch ShowRouting.afterRender(height: snap.height, mode: mode, tty: tty) {
            case .pane:
                try? FileManager.default.removeItem(at: snap.png)
                model.open(url)
                return ShowResult(placed: .pane)
            case .card:
                model.pushCard(SnapshotCardItem(id: UUID(), png: snap.png, source: url))
                return ShowResult(placed: .card)
            case .tty:
                return ShowResult(placed: .tty, png: snap.png.path)
            }
        }
    }
}
