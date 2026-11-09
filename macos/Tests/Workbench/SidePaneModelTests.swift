import Foundation
import Testing
@testable import Ghostty

@MainActor
struct SidePaneModelTests {
    @Test func kinds() {
        #expect(SidePaneKind.of(URL(fileURLWithPath: "/a.HTML")) == .html)
        #expect(SidePaneKind.of(URL(fileURLWithPath: "/a.htm")) == .html)
        #expect(SidePaneKind.of(URL(fileURLWithPath: "/a.md")) == .markdown)
        #expect(SidePaneKind.of(URL(fileURLWithPath: "/a.markdown")) == .markdown)
        #expect(SidePaneKind.of(URL(fileURLWithPath: "/a.pdf")) == .pdf)
        #expect(SidePaneKind.of(URL(fileURLWithPath: "/a.txt")) == nil)
    }

    @Test func historyCapsAtTenAndNavigates() {
        let m = SidePaneModel()
        for i in 0..<12 { m.open(URL(fileURLWithPath: "/d\(i).md")) }
        #expect(m.visible && m.current?.lastPathComponent == "d11.md")
        for _ in 0..<20 { m.back() }
        #expect(m.current?.lastPathComponent == "d2.md" && !m.canGoBack)
        m.forward(); #expect(m.current?.lastPathComponent == "d3.md")
        m.open(URL(fileURLWithPath: "/x.md")); #expect(!m.canGoForward)
    }

    @Test func reopeningSameFileBumpsReload() {
        let m = SidePaneModel(); let u = URL(fileURLWithPath: "/a.md")
        m.open(u); let t = m.reloadToken; m.open(u)
        #expect(m.reloadToken == t + 1 && m.current == u)
    }

    @Test func cardsCapAtThreeNewestFirst() {
        let m = SidePaneModel()
        let items = (0..<4).map { SnapshotCardItem(id: UUID(), png: URL(fileURLWithPath: "/p\($0).png"), source: URL(fileURLWithPath: "/s\($0).html")) }
        items.forEach(m.pushCard)
        #expect(m.cards.map(\.id) == [items[3].id, items[2].id, items[1].id])
        m.dismissCard(items[2].id); #expect(m.cards.count == 2)
    }

    @Test func registryFindsOwner() {
        let a = SidePaneModel(), b = SidePaneModel(); let s = UUID()
        SidePaneRegistry.shared.register(a) { _ in false }
        SidePaneRegistry.shared.register(b) { $0 == s }
        defer { SidePaneRegistry.shared.unregister(a); SidePaneRegistry.shared.unregister(b) }
        #expect(SidePaneRegistry.shared.model(for: s) === b)
        #expect(SidePaneRegistry.shared.model(for: UUID()) == nil)
    }

    @Test func markdownPageUsesBundledScriptsOnly() {
        let html = MarkdownPage.html(markdown: "# Hi\n```mermaid\ngraph LR; a-->b\n```", title: "T", resources: URL(fileURLWithPath: "/R"))
        #expect(html.contains("file:///R/markdown-it.min.js") && html.contains("file:///R/mermaid.min.js"))
        #expect(!html.contains("http://") && !html.contains("https://"))
    }
}
