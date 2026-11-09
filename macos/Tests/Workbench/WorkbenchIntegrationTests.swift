import AppKit
import Foundation
import Testing
import WorkbenchProtocol
@testable import Ghostty

@MainActor
struct WorkbenchIntegrationTests {
    func store() throws -> WorkbenchStore {
        try WorkbenchStore(dbPath: FileManager.default.temporaryDirectory.appendingPathComponent("wi-\(UUID()).db").path)
    }

    @Test func environmentCarriesSurfaceColorAndSocket() throws {
        let s = try store(); let S = UUID(); var env: [String: String] = [:]
        WorkbenchEnvironment.apply(to: &env, surface: S, cwd: "/r", parent: nil, store: s)
        #expect(env["GHOSTTWRITER_SURFACE"] == S.uuidString)
        #expect(ClaudeColor(rawValue: env["TABCOLOR"] ?? "") != nil)
        #expect(env["GHOSTTWRITER_SOCKET"] == SocketPaths.defaultSocket(home: NSHomeDirectory()))
    }

    @Test func splitInheritsTabColor() throws {
        let s = try store(); let A = UUID(), B = UUID()
        var e1: [String: String] = [:], e2: [String: String] = [:]
        WorkbenchEnvironment.apply(to: &e1, surface: A, cwd: "/", parent: nil, store: s)
        WorkbenchEnvironment.apply(to: &e2, surface: B, cwd: "/", parent: A, store: s)
        #expect(e1["TABCOLOR"] == e2["TABCOLOR"])
    }

    @Test func tabsTitlebarBecomesTransparent() {
        #expect(WorkbenchEnvironment.effectiveTitlebarStyle("tabs") == "transparent")
        #expect(WorkbenchEnvironment.effectiveTitlebarStyle("native") == "native")
        #expect(WorkbenchEnvironment.effectiveTitlebarStyle("hidden") == "hidden")
    }

    @Test func gtwIsBundled() {
        let url = Bundle.main.url(forAuxiliaryExecutable: "gtw")
        #expect(url != nil && FileManager.default.isExecutableFile(atPath: url!.path))
    }

    @Test func workbenchMenuHasFourShortcuts() {
        let menu = NSMenu()
        WorkbenchMenu.install(in: menu, target: NSObject())
        let keys = menu.items.first?.submenu?.items.filter { !$0.isSeparatorItem }.map { "\($0.keyEquivalentModifierMask.contains([.command, .option]) ? "⌘⌥" : "")\($0.keyEquivalent)" }
        #expect(keys == ["⌘⌥s", "⌘⌥p", "⌘⌥r", "⌘⌥g"])
    }
}
