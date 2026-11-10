import AppKit
import SwiftUI

/// A terminal window's layout: the sidebar, the terminal with its snapshot cards, and the
/// side pane, side by side. The sidebar and the side pane each carry their own drag handle
/// on the edge they share with the terminal.
struct WorkbenchContainer<Content: View>: View {
    @ObservedObject private var paneModel: SidePaneModel
    private let store: WorkbenchStore
    private let background: Color
    private let focusedSurface: (NSWindow) -> UUID?
    private let content: Content

    @StateObject private var bridge: BridgeHolder
    @AppStorage("workbench.sidebarVisible") private var sidebarVisible = true
    @AppStorage(SidePane.fractionKey) private var paneFraction: Double = SidePane.defaultFraction
    @State private var width: CGFloat = 0

    init(
        window: NSWindow?,
        paneModel: SidePaneModel,
        store: WorkbenchStore,
        background: Color,
        focusedSurface: @escaping (NSWindow) -> UUID?,
        @ViewBuilder content: () -> Content
    ) {
        self.paneModel = paneModel
        self.store = store
        self.background = background
        self.focusedSurface = focusedSurface
        self.content = content()
        _bridge = StateObject(wrappedValue: BridgeHolder(window: window))
    }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible, let bridge = bridge.bridge {
                WorkbenchSidebar(store: store, bridge: bridge, background: background, focusedSurface: focusedSurface)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    SnapshotCardView(model: paneModel)
                }

            if paneModel.visible, paneModel.current != nil {
                // 45% of the window by default (constraint 6); the pane's handle changes it.
                SidePane(model: paneModel)
                    .frame(width: (width * SidePane.clamp(paneFraction)).rounded())
            }
        }
        .onAppear { bridge.connect() }
        // Measured in the background so the terminal's ideal size still sizes new windows.
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { width = geo.size.width }
                .onChange(of: geo.size.width) { _, new in width = new }
        })
    }
}

/// Keeps one `TabGroupBridge` for the life of the container's view.
@MainActor
private final class BridgeHolder: ObservableObject {
    @Published private(set) var bridge: TabGroupBridge?
    private weak var window: NSWindow?

    init(window: NSWindow?) {
        self.window = window
    }

    /// Creates the bridge on the next run-loop turn. AppKit builds a window's tab group
    /// lazily and lays the window out while doing so, which traps ("setting value during
    /// update") when the first access comes from inside a SwiftUI update.
    func connect() {
        guard bridge == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.bridge == nil, let window = self.window else { return }
            self.bridge = TabGroupBridge(window: window)
        }
    }
}
