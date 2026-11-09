import Foundation

/// Builds the HTML page that renders a Markdown file with the bundled markdown-it and mermaid.
///
/// The page loads its scripts only from `resources` (the app bundle) and makes no network
/// requests. Mermaid fences become `<pre class="mermaid">` and are drawn by `mermaid.run()`.
/// `window.__gtwReady` resolves once rendering, diagrams included, has finished.
enum MarkdownPage {
    static func html(markdown: String, title: String, resources: URL) -> String {
        let markdownIt = resources.appendingPathComponent("markdown-it.min.js").absoluteString
        let mermaid = resources.appendingPathComponent("mermaid.min.js").absoluteString
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapeHTML(title))</title>
        <style>\(style)</style>
        <script src="\(escapeHTML(markdownIt))"></script>
        <script src="\(escapeHTML(mermaid))"></script>
        </head>
        <body>
        <article id="content"></article>
        <script type="application/json" id="source">\(jsonString(markdown))</script>
        <script>\(script)</script>
        </body>
        </html>
        """
    }

    /// `text` as a JSON string literal that is safe inside a `<script>` element.
    static func jsonString(_ text: String) -> String {
        let data = (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let script = """
    window.__gtwReady = (async function () {
      var source = JSON.parse(document.getElementById('source').textContent);
      var md = window.markdownit({ html: true });
      var fence = md.renderer.rules.fence;
      md.renderer.rules.fence = function (tokens, idx, options, env, self) {
        var token = tokens[idx];
        var lang = token.info.trim().split(/\\s+/)[0];
        if (lang === 'mermaid') {
          return '<pre class="mermaid">' + md.utils.escapeHtml(token.content) + '</pre>\\n';
        }
        return fence(tokens, idx, options, env, self);
      };
      document.getElementById('content').innerHTML = md.render(source);
      if (window.mermaid && document.querySelector('pre.mermaid')) {
        var dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        window.mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: dark ? 'dark' : 'default' });
        try { await window.mermaid.run({ querySelector: 'pre.mermaid' }); } catch (e) { console.error(e); }
      }
    })();
    """

    private static let style = """
    :root { color-scheme: light dark; }
    body { margin: 0; font: 14px/1.6 -apple-system, BlinkMacSystemFont, sans-serif;
      color: #1f2328; background: #ffffff; }
    @media (prefers-color-scheme: dark) { body { color: #e6edf3; background: #0d1117; } }
    article { max-width: 860px; margin: 0 auto; padding: 20px 24px 48px; overflow-wrap: break-word; }
    h1, h2 { border-bottom: 1px solid rgba(128,128,128,0.3); padding-bottom: 0.3em; }
    pre, code { font: 12.5px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace; }
    pre { padding: 12px 14px; border-radius: 6px; overflow: auto; background: rgba(128,128,128,0.12); }
    :not(pre) > code { padding: 0.15em 0.35em; border-radius: 4px; background: rgba(128,128,128,0.15); }
    pre.mermaid { background: transparent; text-align: center; }
    table { border-collapse: collapse; } th, td { border: 1px solid rgba(128,128,128,0.35); padding: 4px 10px; }
    blockquote { margin: 0; padding: 0 1em; border-left: 4px solid rgba(128,128,128,0.35); opacity: 0.85; }
    img { max-width: 100%; }
    a { color: #2f81f7; }
    """
}
