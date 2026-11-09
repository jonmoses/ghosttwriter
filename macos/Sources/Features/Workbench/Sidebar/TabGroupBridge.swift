import AppKit

/// Drives a window's native tab group from the sidebar: the tab bar stays
/// hidden, and the sidebar selects and reorders tabs through this bridge so the
/// tab-group order matches the sidebar order (⌘1–⌘9 follow the sidebar rows).
@MainActor
final class TabGroupBridge {
    private weak var window: NSWindow?
    private weak var observedGroup: NSWindowTabGroup?
    private var observations: [NSKeyValueObservation] = []

    /// Called after the tab group's windows or selected window change.
    var onChange: (() -> Void)?

    init(window: NSWindow) {
        self.window = window
        observe()
    }

    /// The tabs of the window's group in tab-group order, or just the window
    /// when it has no group.
    func orderedWindows() -> [NSWindow] {
        guard let window else { return [] }
        return window.tabGroup?.windows ?? [window]
    }

    func select(_ window: NSWindow) {
        guard let group = tabGroup() else { return }
        group.selectedWindow = window
    }

    func move(_ window: NSWindow, to index: Int) {
        guard let group = tabGroup(),
              let current = group.windows.firstIndex(where: { $0 === window }),
              current != index else { return }
        let selected = group.selectedWindow
        group.removeWindow(window)
        group.insertWindow(window, at: min(max(index, 0), group.windows.count))
        if let selected { group.selectedWindow = selected }
        hideTabBar()
    }

    /// Hides the native tab bar. AppKit's `toggleTabBar(_:)` only hides it
    /// while the group has a single tab, so with more tabs this falls back to
    /// the tab group's private `_setTabBarIsVisible:force:`.
    func hideTabBar() {
        guard let window, let group = window.tabGroup, group.isTabBarVisible else { return }
        window.toggleTabBar(nil)
        guard group.isTabBarVisible else { return }
        Self.forceHide(group)
    }

    // MARK: Private

    private func tabGroup() -> NSWindowTabGroup? {
        observeIfGroupChanged()
        return window?.tabGroup
    }

    private func observeIfGroupChanged() {
        if window?.tabGroup !== observedGroup { observe() }
    }

    private func observe() {
        observations.forEach { $0.invalidate() }
        observations = []
        observedGroup = window?.tabGroup
        guard let group = observedGroup else { return }
        observations.append(group.observe(\.windows, options: [.new]) { [weak self] _, _ in
            Self.onMain { self?.groupDidChange() }
        })
        observations.append(group.observe(\.selectedWindow, options: [.new]) { [weak self] _, _ in
            Self.onMain { self?.groupDidChange() }
        })
    }

    private func groupDidChange() {
        observeIfGroupChanged()
        hideTabBar()
        onChange?()
    }

    private static let forceVisibleSelector = NSSelectorFromString("_setTabBarIsVisible:force:")

    private static func forceHide(_ group: NSWindowTabGroup) {
        let sel = forceVisibleSelector
        guard group.responds(to: sel) else { return }
        typealias SetVisible = @convention(c) (AnyObject, Selector, Bool, Bool) -> Void
        let imp = unsafeBitCast(group.method(for: sel), to: SetVisible.self)
        imp(group, sel, false, true)
    }

    private nonisolated static func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            DispatchQueue.main.async { body() }
        }
    }
}
