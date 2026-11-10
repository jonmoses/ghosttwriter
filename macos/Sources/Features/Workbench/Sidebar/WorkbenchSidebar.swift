import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The window's tab list grouped by repo, with the goals panel for the focused surface below it.
/// Row and group order drive the native tab-group order through `TabGroupBridge` (constraint 4).
struct WorkbenchSidebar: View {
    static let minWidth: Double = 180
    static let maxWidth: Double = 400

    @ObservedObject private var store: WorkbenchStore
    private let bridge: TabGroupBridge
    /// The terminal's configured background at its configured opacity, so the sidebar reads
    /// as part of the same window instead of a separate translucent panel.
    private let background: Color
    private let focusedSurface: (NSWindow) -> UUID?

    @StateObject private var tabsChanged = TabsChangeObserver()
    @AppStorage("workbench.sidebarWidth") private var width: Double = 240
    @State private var collapsed: Set<String> = []
    @State private var dragStartWidth: Double?

    init(
        store: WorkbenchStore,
        bridge: TabGroupBridge,
        background: Color,
        focusedSurface: @escaping (NSWindow) -> UUID?
    ) {
        self.store = store
        self.bridge = bridge
        self.background = background
        self.focusedSurface = focusedSurface
    }

    var body: some View {
        _ = tabsChanged.tick // re-render when the tab group changes
        let windows = bridge.orderedWindows()
        let tabs = windows.compactMap { w in
            focusedSurface(w).map { SidebarTab(surface: $0, window: ObjectIdentifier(w)) }
        }
        let sections = SidebarModel.sections(tabs: tabs, store: store)
        let order = SidebarModel.tabOrder(sections)
        let selected = selectedWindow(windows)

        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                list(sections, selected: selected.map(ObjectIdentifier.init))
                Divider()
                GoalsPanel(store: store, surface: selected.flatMap(focusedSurface))
            }
            .frame(width: Self.clamp(width))
            resizeHandle
        }
        .background(background)
        .onAppear {
            tabsChanged.attach(bridge)
            syncNativeOrder(order)
        }
        .onChange(of: order) { _, new in syncNativeOrder(new) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            tabsChanged.tick += 1
        }
    }

    // MARK: List

    private func list(_ sections: [SidebarSection], selected: ObjectIdentifier?) -> some View {
        List {
            ForEach(sections) { section in
                Section {
                    if !collapsed.contains(section.id) {
                        ForEach(section.rows) { row in
                            SidebarRowView(row: row)
                                .listRowBackground(
                                    row.window == selected
                                        ? RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.2))
                                        : nil)
                                .onTapGesture { select(row) }
                                .contextMenu { pinButton(row) }
                        }
                        .onMove { from, to in moveRows(in: section, from: from, to: to, sections: sections) }
                    }
                } header: {
                    header(section, sections: sections)
                }
            }
        }
        .listStyle(.sidebar)
        // The sidebar style otherwise draws its own vibrancy material over `background`.
        .scrollContentBackground(.hidden)
    }

    private func header(_ section: SidebarSection, sections: [SidebarSection]) -> some View {
        Button {
            if collapsed.contains(section.id) {
                collapsed.remove(section.id)
            } else {
                collapsed.insert(section.id)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: collapsed.contains(section.id) ? "chevron.right" : "chevron.down")
                    .font(.caption2)
                Text(section.label)
                Spacer()
                Text("\(section.rows.count)").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.id.isEmpty || section.id == SidebarModel.pinnedID ? section.label : section.id)
        .draggable(GroupDrag.prefix + section.id)
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first, item.hasPrefix(GroupDrag.prefix) else { return false }
            return moveGroup(String(item.dropFirst(GroupDrag.prefix.count)), onto: section.id, sections: sections)
        }
    }

    @ViewBuilder
    private func pinButton(_ row: SidebarRow) -> some View {
        if row.pinned {
            Button("Unpin") { setPinned(row, false) }
        } else {
            Button("Pin") { setPinned(row, true) }
        }
    }

    private var resizeHandle: some View {
        // A hairline separator centered in the 5 pt drag target.
        Rectangle()
            .fill(Color.clear)
            .frame(width: 5)
            .overlay(Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1))
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartWidth ?? Self.clamp(width)
                        if dragStartWidth == nil { dragStartWidth = start }
                        width = Self.clamp(start + value.translation.width)
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
    }

    // MARK: Actions

    private func select(_ row: SidebarRow) {
        guard let w = window(for: row.window) else { return }
        bridge.select(w)
        w.makeKeyAndOrderFront(nil)
    }

    private func setPinned(_ row: SidebarRow, _ pin: Bool) {
        guard let record = try? store.record(for: row.id, create: pin) else { return }
        if pin {
            store.pinned.insert(record.id)
        } else {
            store.pinned.remove(record.id)
        }
    }

    /// Reorders rows inside one section, then moves the native tabs to match (constraints 4 and 10).
    private func moveRows(in section: SidebarSection, from: IndexSet, to: Int, sections: [SidebarSection]) {
        var updated = sections
        guard let i = updated.firstIndex(where: { $0.id == section.id }) else { return }
        let moved = from.map { updated[i].rows[$0] }
        guard moved.allSatisfy({ SidebarModel.canMove($0, toSection: section.id, sections: sections) }) else { return }
        updated[i].rows.move(fromOffsets: from, toOffset: to)
        syncNativeOrder(SidebarModel.tabOrder(updated))
    }

    /// Drops group `id` onto group `target`: before it when dragged up, after it when dragged
    /// down, and stores the new order (constraint 10).
    private func moveGroup(_ id: String, onto target: String, sections: [SidebarSection]) -> Bool {
        guard id != target, id != SidebarModel.pinnedID, target != SidebarModel.pinnedID else { return false }
        var ids = sections.map(\.id).filter { $0 != SidebarModel.pinnedID }
        guard let from = ids.firstIndex(of: id), let targetIndex = ids.firstIndex(of: target) else { return false }
        ids.remove(at: from)
        guard let t = ids.firstIndex(of: target) else { return false }
        ids.insert(id, at: from < targetIndex ? t + 1 : t)
        // Remembered roots with no tab in this window keep their place after the visible ones.
        store.groupOrder = ids + store.groupOrder.filter { !ids.contains($0) }
        return true
    }

    /// Moves the native tabs so the tab-group order equals the sidebar order.
    private func syncNativeOrder(_ order: [ObjectIdentifier]) {
        let windows = bridge.orderedWindows()
        guard windows.map(ObjectIdentifier.init) != order else { return }
        let byID = Dictionary(windows.map { (ObjectIdentifier($0), $0) }, uniquingKeysWith: { a, _ in a })
        for (index, id) in order.enumerated() {
            if let w = byID[id] { bridge.move(w, to: index) }
        }
    }

    // MARK: Helpers

    private func window(for id: ObjectIdentifier) -> NSWindow? {
        bridge.orderedWindows().first { ObjectIdentifier($0) == id }
    }

    /// The key window when it is one of this group's tabs, else the group's selected tab.
    private func selectedWindow(_ windows: [NSWindow]) -> NSWindow? {
        if let key = NSApp.keyWindow, windows.contains(where: { $0 === key }) { return key }
        return windows.first?.tabGroup?.selectedWindow ?? windows.first
    }

    static func clamp(_ w: Double) -> Double {
        min(max(w, minWidth), maxWidth)
    }
}

private enum GroupDrag {
    static let prefix = "ghosttwriter-group:"
}

/// Bumps `tick` whenever the bridge reports a tab-group change.
@MainActor
private final class TabsChangeObserver: ObservableObject {
    @Published var tick = 0
    private weak var attached: TabGroupBridge?

    func attach(_ bridge: TabGroupBridge) {
        guard attached !== bridge else { return }
        attached = bridge
        let previous = bridge.onChange
        bridge.onChange = { [weak self] in
            previous?()
            self?.tick += 1
        }
    }
}
