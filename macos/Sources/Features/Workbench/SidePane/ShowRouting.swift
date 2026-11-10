import CoreGraphics
import Foundation
import WorkbenchProtocol

/// What `show` should do with a file before any rendering.
enum ShowPreflight: Equatable {
    case pane, render, unsupported
}

/// The inline rule for `gtw show` (spec Figure 5).
enum ShowRouting {
    static let maxInlineBytes = 200 * 1024
    static let maxInlineHeight: CGFloat = 600

    /// Decides from the file alone whether it goes to the pane, gets rendered, or has no preview.
    static func preflight(path: String, mode: ShowMode) throws -> ShowPreflight {
        let url = URL(fileURLWithPath: path)
        guard let kind = SidePaneKind.of(url) else { return .unsupported }
        guard FileManager.default.fileExists(atPath: path) else { throw WorkbenchError.notFound(path) }
        switch kind {
        case .markdown, .pdf: return .pane
        case .html:
            if mode == .pane { return .pane }
            if mode == .inline { return .render }
            let size = (try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? .max
            if size > maxInlineBytes { return .pane }
            let text = try String(contentsOfFile: path, encoding: .utf8)
            return text.range(of: "<script", options: .caseInsensitive) == nil ? .render : .pane
        }
    }

    /// Places a rendered snapshot: too tall for `auto` goes to the pane, otherwise tty or card.
    static func afterRender(height: CGFloat, mode: ShowMode, tty: Bool) -> ShowPlacement {
        if mode == .auto && height > maxInlineHeight { return .pane }
        return tty ? .tty : .card
    }

    /// The width a snapshot is rendered at for a terminal of `terminalWidth` points.
    static func renderWidth(terminalWidth: CGFloat) -> CGFloat {
        min(terminalWidth - 24, 1000)
    }
}
