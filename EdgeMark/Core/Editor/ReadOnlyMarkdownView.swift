import SwiftUI
import WebKit

/// Non-editable Markdown viewer with WYSIWYG rendering via CodeMirror 6.
/// Used for previewing trashed notes. Markers are permanently hidden.
struct ReadOnlyMarkdownView: NSViewRepresentable {
    let content: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)

        // Full transparency stack
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.backgroundColor = .clear
        webView.layer?.isOpaque = false

        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.pendingContent = content

        // Load editor.html with readOnly param
        if let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html") {
            var components = URLComponents(url: htmlURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "readOnly", value: "true")]
            if let readOnlyURL = components.url {
                webView.loadFileURL(readOnlyURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
            }
        }

        return webView
    }

    func updateNSView(_: WKWebView, context: Context) {
        guard context.coordinator.lastContent != content else { return }
        context.coordinator.lastContent = content
        if context.coordinator.isReady {
            context.coordinator.setContent(content)
        } else {
            context.coordinator.pendingContent = content
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var isReady = false
        var pendingContent: String?
        var lastContent: String?

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            // editor.html signals "ready" via postMessage, but for read-only
            // we don't have a message handler — just wait for navigation to finish
            // and then inject content + theme.
            isReady = true

            // Sync theme
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let theme = isDark ? "dark" : "light"
            webView.evaluateJavaScript("window.editorAPI.setTheme('\(theme)')")

            if let content = pendingContent {
                pendingContent = nil
                setContent(content)
            }
        }

        func setContent(_ content: String) {
            guard let webView else { return }
            let data = try! JSONEncoder().encode(content)
            let json = String(data: data, encoding: .utf8)!
            webView.evaluateJavaScript("window.editorAPI.setContent(\(json))")
            lastContent = content
        }
    }
}
