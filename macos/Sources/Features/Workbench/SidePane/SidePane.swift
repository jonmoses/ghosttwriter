import AppKit
import PDFKit
import SwiftUI
import WebKit

/// The per-tab side pane: a header with history and "Open in default app", and the current
/// document rendered as HTML, Markdown or PDF. It reloads when the file changes on disk,
/// keeping the scroll position (HTML, Markdown) or page (PDF).
struct SidePane: View {
    static let fractionKey = "workbench.sidePaneFraction"
    static let defaultFraction = 0.45
    static let fractionRange: ClosedRange<Double> = 0.25...0.70

    @ObservedObject private var model: SidePaneModel
    @AppStorage(SidePane.fractionKey) private var fraction: Double = SidePane.defaultFraction
    @State private var dragStart: (width: CGFloat, fraction: Double)?
    @State private var paneWidth: CGFloat = 0
    @State private var cursorPushed = false

    init(model: SidePaneModel) {
        self.model = model
    }

    /// The pane's width inside a container of `width`, from the remembered fraction.
    static func width(forContainerWidth width: CGFloat, defaults: UserDefaults = .standard) -> CGFloat {
        let stored = defaults.object(forKey: fractionKey) as? Double ?? defaultFraction
        return (width * clamp(stored)).rounded()
    }

    static func clamp(_ fraction: Double) -> Double {
        min(max(fraction, fractionRange.lowerBound), fractionRange.upperBound)
    }

    var body: some View {
        HStack(spacing: 0) {
            resizeHandle
            VStack(spacing: 0) {
                header
                Divider()
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { paneWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, width in paneWidth = width }
        })
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Button { model.back() } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoBack)
                .help("Back")
            Button { model.forward() } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoForward)
                .help("Forward")
            Text(model.current?.lastPathComponent ?? "")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.current?.path ?? "")
            Spacer(minLength: 4)
            Button {
                if let url = model.current { NSWorkspace.shared.open(url) }
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .disabled(model.current == nil)
            .help("Open in default app")
            .accessibilityLabel("Open in default app")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .frame(height: 30)
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        if let url = model.current {
            switch SidePaneKind.of(url) {
            case .html:
                SidePaneWebView(url: url, kind: .html, reloadToken: model.reloadToken, model: model)
            case .markdown:
                SidePaneWebView(url: url, kind: .markdown, reloadToken: model.reloadToken, model: model)
            case .pdf:
                SidePanePDFView(url: url, reloadToken: model.reloadToken)
            case nil:
                Text("Can't show \(url.lastPathComponent)").foregroundStyle(.secondary)
            }
        } else {
            Color.clear
        }
    }

    // MARK: Resizing

    /// Dragging the leading edge changes the remembered fraction. The container's width is
    /// the pane's own width divided by the fraction it was laid out with.
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { inside in setResizeCursor(inside) }
            .onDisappear { setResizeCursor(false) }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? (paneWidth, Self.clamp(fraction))
                        dragStart = start
                        guard start.width > 0 else { return }
                        let container = start.width / CGFloat(start.fraction)
                        fraction = Self.clamp(start.fraction - Double(value.translation.width / container))
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }

    /// Pushes the resize cursor at most once and pops only what was pushed, so the cursor
    /// stack stays balanced even when the pane disappears while hovered.
    private func setResizeCursor(_ on: Bool) {
        guard on != cursorPushed else { return }
        cursorPushed = on
        if on { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
    }
}

// MARK: - Web view

/// Shows an HTML file directly, or a Markdown file through `MarkdownPage`.
private struct SidePaneWebView: NSViewRepresentable {
    let url: URL
    let kind: SidePaneKind
    let reloadToken: Int
    let model: SidePaneModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.show(url: url, kind: kind, token: reloadToken)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private weak var model: SidePaneModel?
        private var url: URL?
        private var kind: SidePaneKind = .html
        private var token = 0
        private var watcher: FileWatcher?
        private var pendingScroll: Double?
        private var generation = 0
        private var page: URL?

        init(model: SidePaneModel) { self.model = model }

        func show(url: URL, kind: SidePaneKind, token: Int) {
            if url != self.url || kind != self.kind {
                self.url = url
                self.kind = kind
                self.token = token
                watcher?.stop()
                watcher = FileWatcher(url: url) { [weak self] in self?.reload() }
                watcher?.start()
                pendingScroll = nil
                load()
            } else if token != self.token {
                self.token = token
                reload()
            }
        }

        /// Reloads the current file, restoring the scroll position once it has loaded.
        func reload() {
            guard let webView else { return }
            generation += 1
            let expected = generation
            webView.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
                MainActor.assumeIsolated {
                    guard let self, self.generation == expected else { return }
                    self.pendingScroll = (value as? NSNumber)?.doubleValue
                    self.load()
                }
            }
        }

        func teardown() {
            watcher?.stop()
            watcher = nil
            removePage()
        }

        private func load() {
            guard let webView, let url else { return }
            generation += 1
            let dir = url.deletingLastPathComponent()
            switch kind {
            case .markdown:
                loadMarkdown(url, dir: dir, in: webView)
            default:
                removePage()
                webView.loadFileURL(url, allowingReadAccessTo: dir)
            }
        }

        /// Loads the rendered page from a temp file. A page loaded from a string cannot read
        /// the bundled scripts, and WebKit grants read access to one directory per load, so the
        /// grant is the common ancestor of the page, the document's directory and the
        /// resources, and `<base>` resolves the document's relative links and images.
        private func loadMarkdown(_ url: URL, dir: URL, in webView: WKWebView) {
            let resources = MarkdownPage.bundledResources
            let text: String
            if let data = try? Data(contentsOf: url) {
                text = String(decoding: data, as: UTF8.self)
            } else {
                text = "*\(url.lastPathComponent) could not be read.*"
            }
            var html = MarkdownPage.html(markdown: text, title: url.lastPathComponent, resources: resources)
            html = html.replacingOccurrences(
                of: "<head>",
                with: "<head>\n<base href=\"\(MarkdownPage.escapeHTML(dir.absoluteString))\">")
            let folder = Self.pageFolder
            let file = folder.appendingPathComponent("\(UUID().uuidString).html")
            removePage()
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try html.write(to: file, atomically: true, encoding: .utf8)
            } catch {
                webView.loadHTMLString(html, baseURL: dir)
                return
            }
            page = file
            webView.loadFileURL(file, allowingReadAccessTo: Self.commonAncestor([folder, dir, resources]))
        }

        /// The folder for rendered Markdown pages. The first use in a process clears pages
        /// left behind by an earlier run that did not tear its panes down (a crash).
        static let pageFolder: URL = {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("Ghosttwriter-SidePane", isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            return folder
        }()

        private func removePage() {
            if let page { try? FileManager.default.removeItem(at: page) }
            page = nil
        }

        static func commonAncestor(_ urls: [URL]) -> URL {
            let paths = urls.map { $0.standardizedFileURL.resolvingSymlinksInPath().pathComponents }
            guard var common = paths.first else { return URL(fileURLWithPath: "/") }
            for path in paths.dropFirst() {
                common = Array(zip(common, path).prefix { $0 == $1 }.map(\.0))
            }
            return URL(fileURLWithPath: NSString.path(withComponents: common.isEmpty ? ["/"] : common),
                       isDirectory: true)
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let y = pendingScroll else { return }
            pendingScroll = nil
            // Markdown pages render (and draw diagrams) asynchronously; wait for them first.
            webView.evaluateJavaScript(
                "(window.__gtwReady || Promise.resolve()).then(function () { window.scrollTo(0, \(y)); }); 0")
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard action.navigationType == .linkActivated, let target = action.request.url else {
                decisionHandler(.allow)
                return
            }
            // Same-page anchors stay in the page. In a Markdown page `<base>` points at the
            // document's directory, so "#x" arrives as "<dir>/#x"; jump to it with
            // `location.hash`, which resolves against the page itself.
            if let fragment = SidePaneLinks.inPageFragment(
                target, page: webView.url, document: url ?? target,
                baseDirectory: kind == .markdown ? url?.deletingLastPathComponent() : nil) {
                if let current = webView.url, SidePaneLinks.stripFragment(current) == SidePaneLinks.stripFragment(target) {
                    decisionHandler(.allow)
                } else {
                    decisionHandler(.cancel)
                    let literal = (try? JSONEncoder().encode("#" + fragment)).map { String(decoding: $0, as: UTF8.self) }
                    if let literal { webView.evaluateJavaScript("location.hash = \(literal); 0") }
                }
                return
            }
            decisionHandler(.cancel)
            if target.isFileURL, SidePaneKind.of(target) != nil {
                model?.open(target)
            } else {
                NSWorkspace.shared.open(target)
            }
        }
    }
}

/// Link classification for the side pane's web view.
enum SidePaneLinks {
    /// The fragment of `target` when it points into the page being shown: the page itself,
    /// the source document, or (when a `<base>` was injected) the base directory with a
    /// fragment. Returns nil for links that leave the page.
    static func inPageFragment(_ target: URL, page: URL?, document: URL, baseDirectory: URL?) -> String? {
        guard let fragment = target.fragment else { return nil }
        let bare = stripFragment(target)
        var same: [URL] = [stripFragment(document)]
        if let page { same.append(stripFragment(page)) }
        if let baseDirectory { same.append(stripFragment(baseDirectory)) }
        return same.contains { sameLocation($0, bare) } ? fragment : nil
    }

    static func stripFragment(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        parts.fragment = nil
        return parts.url ?? url
    }

    private static func sameLocation(_ a: URL, _ b: URL) -> Bool {
        if a.isFileURL && b.isFileURL {
            return a.standardizedFileURL.path == b.standardizedFileURL.path
        }
        return a.absoluteString == b.absoluteString
    }
}

extension MarkdownPage {
    /// The directory holding the bundled markdown-it and mermaid scripts.
    static var bundledResources: URL {
        Bundle.main.url(forResource: "markdown-it.min", withExtension: "js")?.deletingLastPathComponent()
            ?? Bundle.main.resourceURL
            ?? Bundle.main.bundleURL
    }
}

// MARK: - PDF view

private struct SidePanePDFView: NSViewRepresentable {
    let url: URL
    let reloadToken: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        context.coordinator.pdfView = view
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.show(url: url, token: reloadToken)
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        coordinator.watcher?.stop()
        coordinator.watcher = nil
    }

    @MainActor
    final class Coordinator {
        weak var pdfView: PDFView?
        var watcher: FileWatcher?
        private var url: URL?
        private var token = 0

        func show(url: URL, token: Int) {
            if url != self.url {
                self.url = url
                self.token = token
                watcher?.stop()
                watcher = FileWatcher(url: url) { [weak self] in self?.load(keepPage: true) }
                watcher?.start()
                load(keepPage: false)
            } else if token != self.token {
                self.token = token
                load(keepPage: true)
            }
        }

        /// Loads the document, going back to the page that was showing (constraint 22).
        private func load(keepPage: Bool) {
            guard let pdfView, let url else { return }
            var index: Int?
            if keepPage, let document = pdfView.document, let page = pdfView.currentPage {
                index = document.index(for: page)
            }
            guard let document = PDFDocument(url: url) else { return }
            pdfView.document = document
            if let index, document.pageCount > 0, let page = document.page(at: min(index, document.pageCount - 1)) {
                pdfView.go(to: page)
            }
        }
    }
}
