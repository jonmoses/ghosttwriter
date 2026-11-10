import Foundation
import WorkbenchProtocol

/// One native tab: the surface shown for it and the tab's window.
struct SidebarTab: Equatable {
    var surface: UUID
    var window: ObjectIdentifier
}

/// One sidebar row (spec constraint 8).
struct SidebarRow: Identifiable, Equatable {
    var id: UUID // surface
    var window: ObjectIdentifier
    var title: String
    var cwdName: String
    var repoRoot: String?
    var color: ClaudeColor
    var gitLabel: String
    var dirty: Bool
    var badge: Badge
    var progress: String?
    var pinned: Bool
}

/// A group of rows: "pinned", a repo root, or "" for non-repo tabs.
struct SidebarSection: Identifiable, Equatable {
    var id: String // "pinned", repo root, or ""
    var label: String
    var rows: [SidebarRow]
}

/// Builds the sidebar's sections from the tab order and the store (constraints 8–10).
@MainActor
enum SidebarModel {
    static let pinnedID = "pinned"
    static let otherID = ""

    static func sections(tabs: [SidebarTab], store: WorkbenchStore) -> [SidebarSection] {
        let rows = tabs.map { row(for: $0, store: store) }

        var pinned: [SidebarRow] = []
        var groups: [String: [SidebarRow]] = [:]
        var firstSeen: [String] = []
        for row in rows {
            if row.pinned {
                pinned.append(row)
                continue
            }
            let key = row.repoRoot ?? otherID
            if groups[key] == nil { firstSeen.append(key) }
            groups[key, default: []].append(row)
        }

        var order: [String] = []
        for key in store.groupOrder where groups[key] != nil && !order.contains(key) {
            order.append(key)
        }
        for key in firstSeen where key != otherID && !order.contains(key) {
            order.append(key)
        }
        if groups[otherID] != nil && !order.contains(otherID) { order.append(otherID) }

        var result: [SidebarSection] = []
        if !pinned.isEmpty {
            result.append(SidebarSection(id: pinnedID, label: "Pinned", rows: pinned))
        }
        for key in order {
            result.append(SidebarSection(id: key, label: label(forGroup: key), rows: groups[key] ?? []))
        }
        return result
    }

    static func gitLabel(_ g: GitState?) -> String {
        guard let g else { return "" }
        if g.timedOut { return g.branch + " ?" }
        var s = g.branch
        if g.ahead > 0 { s += " ↑\(g.ahead)" }
        if g.behind > 0 { s += " ↓\(g.behind)" }
        return s
    }

    /// True only when the row stays in its own section.
    static func canMove(_ row: SidebarRow, toSection id: String, sections: [SidebarSection]) -> Bool {
        guard let own = sections.first(where: { $0.rows.contains(where: { $0.id == row.id }) }) else { return false }
        return own.id == id
    }

    /// The windows in sidebar order, top to bottom, each once.
    static func tabOrder(_ sections: [SidebarSection]) -> [ObjectIdentifier] {
        var seen: Set<ObjectIdentifier> = []
        var order: [ObjectIdentifier] = []
        for row in sections.flatMap(\.rows) where seen.insert(row.window).inserted {
            order.append(row.window)
        }
        return order
    }

    // MARK: Private

    private static func label(forGroup key: String) -> String {
        key == otherID ? "Other" : (key as NSString).lastPathComponent
    }

    private static func row(for tab: SidebarTab, store: WorkbenchStore) -> SidebarRow {
        let live = store.liveSurfaces[tab.surface]
        let record = store.surfaceRecord[tab.surface].flatMap { store.records[$0] }
        let cwd = live?.cwd ?? record?.cwd ?? ""
        let root = store.repoRoots[cwd]
        let git = root.flatMap { store.git[$0] }
        let title: String
        if let t = record?.title, !t.isEmpty {
            title = t
        } else {
            title = live?.title ?? ""
        }
        let progress: String? = record.flatMap { r in
            r.goals.isEmpty ? nil : "\(r.goals.filter(\.done).count)/\(r.goals.count)"
        }
        return SidebarRow(
            id: tab.surface,
            window: tab.window,
            title: title,
            cwdName: (cwd as NSString).lastPathComponent,
            repoRoot: root,
            color: live?.color ?? record?.color ?? .blue,
            gitLabel: gitLabel(git),
            dirty: git?.isDirty ?? false,
            badge: WorkbenchStore.badge(for: record),
            progress: progress,
            pinned: record.map { store.pinned.contains($0.id) } ?? false)
    }
}
