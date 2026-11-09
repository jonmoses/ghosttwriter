import AppKit
import SwiftUI

/// A terminal window's layout: the sidebar, the terminal with its snapshot cards, and the
/// side pane, side by side. The sidebar and the side pane each carry their own drag handle
/// on the edge they share with the terminal.
struct WorkbenchContainer<Content: View>: View {
    @ObservedObject private var paneModel: SidePaneModel
    private let store: WorkbenchStore
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
        focusedSurface: @escaping (NSWindow) -> UUID?,
        @ViewBuilder content: () -> Content
    ) {
        self.paneModel = paneModel
        self.store = store
        self.focusedSurface = focusedSurface
        self.content = content()
        _bridge = StateObject(wrappedValue: BridgeHolder(window: window))
    }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible, let bridge = bridge.bridge {
                WorkbenchSidebar(store: store, bridge: bridge, focusedSurface: focusedSurface)
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
    let bridge: TabGroupBridge?

    init(window: NSWindow?) {
        bridge = window.map(TabGroupBridge.init(window:))
    }
}
