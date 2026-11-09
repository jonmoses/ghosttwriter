import Foundation
import Testing
import WorkbenchProtocol
@testable import Ghostty

@MainActor
struct ShowRoutingTests {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    func path(_ n: String) -> String { fixtures.appendingPathComponent(n).path }

    @Test func preflightBranches() throws {
        #expect(try ShowRouting.preflight(path: path("small.html"), mode: .auto) == .render)
        #expect(try ShowRouting.preflight(path: path("scripted.html"), mode: .auto) == .pane)
        #expect(try ShowRouting.preflight(path: path("scripted.html"), mode: .inline) == .render)
        #expect(try ShowRouting.preflight(path: path("small.html"), mode: .pane) == .pane)
        let big = FileManager.default.temporaryDirectory.appendingPathComponent("big-\(UUID()).html")
        try String(repeating: "<p>x</p>", count: 30_000).write(to: big, atomically: true, encoding: .utf8)
        #expect(try ShowRouting.preflight(path: big.path, mode: .auto) == .pane)
        #expect(try ShowRouting.preflight(path: "/x/a.md", mode: .inline) == .pane)
        #expect(try ShowRouting.preflight(path: "/x/a.pdf", mode: .auto) == .pane)
        #expect(try ShowRouting.preflight(path: "/x/a.txt", mode: .auto) == .unsupported)
        #expect(throws: WorkbenchError.notFound("/nope/x.html")) { try ShowRouting.preflight(path: "/nope/x.html", mode: .auto) }
    }

    @Test func afterRenderBranches() {
        #expect(ShowRouting.afterRender(height: 400, mode: .auto, tty: false) == .card)
        #expect(ShowRouting.afterRender(height: 400, mode: .auto, tty: true) == .tty)
        #expect(ShowRouting.afterRender(height: 900, mode: .auto, tty: false) == .pane)
        #expect(ShowRouting.afterRender(height: 900, mode: .inline, tty: false) == .card)
        #expect(ShowRouting.afterRender(height: 600, mode: .auto, tty: false) == .card)
    }

    @Test func renderWidthIsCapped() {
        #expect(ShowRouting.renderWidth(terminalWidth: 800) == 776)
        #expect(ShowRouting.renderWidth(terminalWidth: 2000) == 1000)
    }

    @Test func rendererMeasuresHeight() async throws {
        let r = SnapshotRenderer()
        let small = try await r.render(url: fixtures.appendingPathComponent("small.html"), width: 600)
        let tall = try await r.render(url: fixtures.appendingPathComponent("tall.html"), width: 600)
        #expect(small.height <= 600 && tall.height > 600)
        #expect(FileManager.default.fileExists(atPath: small.png.path))
    }

    @Test func routerPlacesSmallAsCardAndTallInPane() async throws {
        let m = SidePaneModel(); let s = UUID()
        SidePaneRegistry.shared.register(m) { $0 == s }; defer { SidePaneRegistry.shared.unregister(m) }
        let router = WorkbenchShowRouter(terminalWidth: { _ in 800 })
        let small = try await router.show(path: path("small.html"), mode: .auto, tty: false, surface: s)
        #expect(small.placed == .card && m.cards.count == 1)
        let tall = try await router.show(path: path("tall.html"), mode: .auto, tty: false, surface: s)
        #expect(tall.placed == .pane && m.current?.lastPathComponent == "tall.html")
        let onTTY = try await router.show(path: path("small.html"), mode: .auto, tty: true, surface: s)
        #expect(onTTY.placed == .tty && onTTY.png != nil)
    }
}
