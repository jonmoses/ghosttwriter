import AppKit

/// The top-level "Workbench" menu and its four shortcuts (constraint 7).
@MainActor
enum WorkbenchMenu {
    static let title = "Workbench"
    static let sidebarVisibleKey = "workbench.sidebarVisible"

    private static let handler = Handler()

    /// Adds the Workbench menu to `menu`, before the Window menu when there is one.
    /// `target` is the app object new windows are opened through when no terminal
    /// window is open (the `AppDelegate` in the app).
    static func install(in menu: NSMenu, target: AnyObject) {
        handler.owner = target
        if let existing = menu.items.first(where: { $0.title == title }) {
            menu.removeItem(existing)
        }

        let submenu = NSMenu(title: title)
        submenu.addItem(item("Toggle Sidebar", "s", #selector(Handler.toggleSidebar(_:))))
        submenu.addItem(item("Toggle Side Pane", "p", #selector(Handler.toggleSidePane(_:))))
        submenu.addItem(item("Resume…", "r", #selector(Handler.resume(_:))))
        submenu.addItem(item("Add Goal", "g", #selector(Handler.addGoal(_:))))

        let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        top.submenu = submenu
        let windowIndex = menu.items.firstIndex { $0.submenu != nil && $0.submenu === NSApp.windowsMenu }
        if let windowIndex {
            menu.insertItem(top, at: windowIndex)
        } else {
            menu.addItem(top)
        }
    }

    private static func item(_ title: String, _ key: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.command, .option]
        item.target = handler
        return item
    }

    /// The terminal controller of the key window, or of the main window when the key
    /// window is not a terminal (a panel, the resume dashboard).
    static func activeController() -> TerminalController? {
        (NSApp.keyWindow?.windowController as? TerminalController)
            ?? (NSApp.mainWindow?.windowController as? TerminalController)
            ?? TerminalController.lastMain
    }

    /// Opens `record` in a new tab of the active window, or in a new window when none is open.
    static func resume(_ record: SessionRecord) {
        if let controller = activeController() {
            controller.newTab(resuming: record)
        } else if let ghostty = (handler.owner as? AppDelegate)?.ghostty ?? (NSApp.delegate as? AppDelegate)?.ghostty {
            TerminalController.openResumed(record, ghostty: ghostty, from: nil)
        }
    }

    @MainActor
    private final class Handler: NSObject {
        weak var owner: AnyObject?

        @objc func toggleSidebar(_ sender: Any?) {
            let defaults = UserDefaults.standard
            let visible = defaults.object(forKey: WorkbenchMenu.sidebarVisibleKey) as? Bool ?? true
            defaults.set(!visible, forKey: WorkbenchMenu.sidebarVisibleKey)
        }

        @objc func toggleSidePane(_ sender: Any?) {
            guard let pane = WorkbenchMenu.activeController()?.workbenchPane else { return }
            pane.visible.toggle()
        }

        @objc func resume(_ sender: Any?) {
            ResumeDashboard.show(store: .shared) { record in WorkbenchMenu.resume(record) }
        }

        @objc func addGoal(_ sender: Any?) {
            let defaults = UserDefaults.standard
            let wasVisible = defaults.object(forKey: WorkbenchMenu.sidebarVisibleKey) as? Bool ?? true
            guard !wasVisible else {
                WorkbenchFocus.shared.goalFieldRequested += 1
                return
            }
            defaults.set(true, forKey: WorkbenchMenu.sidebarVisibleKey)
            // The goals panel appears with the sidebar; ask for focus once it is on screen.
            DispatchQueue.main.async {
                WorkbenchFocus.shared.goalFieldRequested += 1
            }
        }
    }
}
