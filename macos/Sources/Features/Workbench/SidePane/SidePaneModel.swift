import Foundation

/// The kinds of document the side pane can show.
enum SidePaneKind: Equatable {
    case html, markdown, pdf

    static func of(_ url: URL) -> SidePaneKind? {
        switch url.pathExtension.lowercased() {
        case "html", "htm": return .html
        case "md", "markdown": return .markdown
        case "pdf": return .pdf
        default: return nil
        }
    }
}

/// One inline snapshot card: the rendered PNG and the file it came from.
struct SnapshotCardItem: Identifiable, Equatable {
    var id: UUID
    var png: URL
    var source: URL
}

/// Per-tab state of the side pane: what it shows, its history and the snapshot card stack.
@MainActor
final class SidePaneModel: ObservableObject {
    static let historyLimit = 10
    static let cardLimit = 3

    @Published var visible: Bool = false
    @Published private(set) var current: URL?
    @Published private(set) var reloadToken: Int = 0
    @Published private(set) var cards: [SnapshotCardItem] = []

    private var history: [URL] = []
    private var index: Int = -1

    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index >= 0 && index < history.count - 1 }

    /// Shows `url`, dropping any forward history. Re-opening the current file reloads it.
    func open(_ url: URL) {
        visible = true
        if url == current {
            reloadToken += 1
            return
        }
        if index < history.count - 1 { history.removeSubrange((index + 1)...) }
        history.append(url)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
        index = history.count - 1
        current = url
    }

    func back() {
        guard canGoBack else { return }
        index -= 1
        current = history[index]
    }

    func forward() {
        guard canGoForward else { return }
        index += 1
        current = history[index]
    }

    /// Puts `card` on top of the stack, pushing out the oldest beyond three.
    func pushCard(_ card: SnapshotCardItem) {
        cards.insert(card, at: 0)
        if cards.count > Self.cardLimit { cards.removeLast(cards.count - Self.cardLimit) }
    }

    func dismissCard(_ id: UUID) {
        cards.removeAll { $0.id == id }
    }
}
