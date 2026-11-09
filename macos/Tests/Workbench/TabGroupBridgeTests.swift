import AppKit
import Testing
@testable import Ghostty

@MainActor
struct TabGroupBridgeTests {
    func makeTabs(_ n: Int) -> [NSWindow] {
        let first = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        first.isReleasedWhenClosed = false; first.tabbingMode = .preferred; first.tabbingIdentifier = "wb-test-\(UUID())"
        var all = [first]
        for _ in 1..<n {
            let w = NSWindow(contentRect: first.frame, styleMask: first.styleMask, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false; w.tabbingMode = .preferred; w.tabbingIdentifier = first.tabbingIdentifier
            first.addTabbedWindow(w, ordered: .above); all.append(w)
        }
        return all
    }

    @Test func hideKeepsTabBarHidden() {
        let tabs = makeTabs(5); defer { tabs.forEach { $0.close() } }
        let b = TabGroupBridge(window: tabs[0])
        b.hideTabBar()
        #expect(tabs[0].tabGroup?.isTabBarVisible == false)
        let extra = NSWindow(contentRect: tabs[0].frame, styleMask: tabs[0].styleMask, backing: .buffered, defer: false)
        extra.isReleasedWhenClosed = false; extra.tabbingMode = .preferred
        tabs[0].addTabbedWindow(extra, ordered: .above); defer { extra.close() }
        b.hideTabBar()
        #expect(tabs[0].tabGroup?.isTabBarVisible == false)
    }

    @Test func moveReordersTabGroup() {
        let tabs = makeTabs(5); defer { tabs.forEach { $0.close() } }
        let b = TabGroupBridge(window: tabs[0])
        b.move(tabs[4], to: 0)
        #expect(b.orderedWindows().first === tabs[4])
        b.move(tabs[4], to: 2)
        #expect(b.orderedWindows().firstIndex { $0 === tabs[4] } == 2)
        #expect(b.orderedWindows().count == 5)
    }

    @Test func selectMakesSelected() {
        let tabs = makeTabs(3); defer { tabs.forEach { $0.close() } }
        let b = TabGroupBridge(window: tabs[0])
        b.select(tabs[2])
        #expect(tabs[0].tabGroup?.selectedWindow === tabs[2])
    }
}
