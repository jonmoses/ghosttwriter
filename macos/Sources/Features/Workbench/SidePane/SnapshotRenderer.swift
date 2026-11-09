import AppKit
import Foundation
import WebKit

/// Renders an HTML file offscreen and writes a PNG snapshot of its top.
@MainActor
final class SnapshotRenderer {
    enum RenderError: Error {
        case snapshotFailed
    }

    /// Nonisolated so it can be a default argument value of `WorkbenchShowRouter.init`.
    nonisolated init() {}

    /// Loads `url` at `width` points, measures its scroll height and snapshots
    /// at most `ShowRouting.maxInlineHeight` points of it.
    func render(url: URL, width: CGFloat) async throws -> (png: URL, height: CGFloat) {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        let loader = LoadDelegate()
        webView.navigationDelegate = loader
        defer { webView.navigationDelegate = nil }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            loader.continuation = cont
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        let measured = try await webView.evaluateJavaScript("document.documentElement.scrollHeight")
        let height = CGFloat((measured as? NSNumber)?.doubleValue ?? 0)

        webView.frame = NSRect(x: 0, y: 0, width: width, height: max(1, min(height, ShowRouting.maxInlineHeight)))
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        let image = try await webView.takeSnapshot(configuration: config)

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:])
        else { throw RenderError.snapshotFailed }
        let png = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gtw-snap-\(UUID().uuidString).png")
        try data.write(to: png)
        return (png, height)
    }

    private final class LoadDelegate: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Error>?

        private func finish(_ result: Result<Void, Error>) {
            continuation?.resume(with: result)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finish(.success(()))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(.failure(error))
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            finish(.failure(error))
        }
    }
}
