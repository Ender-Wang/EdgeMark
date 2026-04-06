import SwiftUI
import WebKit

struct MarkdownEditorView: NSViewRepresentable {
    let noteID: UUID
    let initialContent: String
    let colorScheme: ColorScheme
    let onContentChanged: (String) -> Void
    var onCoordinatorReady: ((Coordinator) -> Void)?
    var onNavigateNext: (() -> Void)?
    var onNavigatePrevious: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "editor")

        let webView = WKWebView(frame: .zero, configuration: config)

        // Full transparency stack — all three are needed for WKWebView
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.backgroundColor = .clear
        webView.layer?.isOpaque = false

        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.currentNoteID = noteID
        // Defer to avoid modifying @State during a SwiftUI layout pass (makeNSView runs in view update)
        let coordinator = context.coordinator
        DispatchQueue.main.async { [onCoordinatorReady] in
            onCoordinatorReady?(coordinator)
        }

        // Load editor.html from app bundle
        if let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html") {
            #if DEBUG
                print("[Editor] Loading editor.html from: \(htmlURL.path)")
            #endif
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            #if DEBUG
                print("[Editor] ERROR: editor.html not found in bundle!")
            #endif
        }

        // Sync theme with macOS appearance
        context.coordinator.syncTheme()

        return webView
    }

    static func dismantleNSView(_: WKWebView, coordinator: Coordinator) {
        coordinator.flushPendingContent()
        coordinator.removeNoteNavMonitor()
        // Remove message handler to break retain cycle
        coordinator.webView?.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
    }

    func updateNSView(_: WKWebView, context: Context) {
        // When switching notes, flush pending save for the OLD note before updating parent.
        // parent.onContentChanged still points to the old note's callback at this point.
        if context.coordinator.currentNoteID != noteID {
            context.coordinator.flushPendingContent()
        }

        context.coordinator.parent = self

        // Re-sync theme whenever SwiftUI re-evaluates (colorScheme change triggers this)
        context.coordinator.syncTheme()

        // Only update content when the note ID changes (user switched notes)
        guard context.coordinator.currentNoteID != noteID else { return }
        context.coordinator.currentNoteID = noteID
        context.coordinator.slashHandler?.dismiss()

        // Set content once the editor is ready
        if context.coordinator.isEditorReady {
            context.coordinator.setContent(initialContent)
        } else {
            context.coordinator.pendingContent = initialContent
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: MarkdownEditorView
        weak var webView: WKWebView?
        var slashHandler: SlashCommandHandler?
        var currentNoteID: UUID?
        var isEditorReady = false
        var pendingContent: String?
        private let saveDebouncer = Debouncer(delay: 1.0)
        /// Most recently known content, used for flush on dismantle and external sync detection.
        var latestContent: String?
        /// True when a debounced save is pending (EdgeMark has unsaved edits).
        var hasPendingChanges: Bool {
            saveDebouncer.isPending
        }

        private var noteNavMonitor: Any?

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
            currentNoteID = parent.noteID
            latestContent = parent.initialContent
        }

        // MARK: - Flush

        func flushPendingContent() {
            saveDebouncer.cancel()
            if let content = latestContent {
                parent.onContentChanged(content)
            }
        }

        // MARK: - JS → Swift Messages

        nonisolated func userContentController(
            _: WKUserContentController,
            didReceive message: WKScriptMessage,
        ) {
            MainActor.assumeIsolated {
                handleMessage(message)
            }
        }

        private func handleMessage(_ message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let action = body["action"] as? String
            else { return }

            #if DEBUG
                let start = CFAbsoluteTimeGetCurrent()
            #endif

            switch action {
            case "ready":
                isEditorReady = true
                let content = pendingContent ?? parent.initialContent
                pendingContent = nil
                #if DEBUG
                    print("[Editor] JS ready. Setting content (\(content.count) chars) for note \(currentNoteID?.uuidString.prefix(8) ?? "nil")")
                #endif
                setContent(content)
                syncTheme()

                // Initialize slash handler with WKWebView bridge
                slashHandler = SlashCommandHandler(webView: webView)
                installNoteNavMonitor()

            case "contentChanged":
                guard let content = body["content"] as? String else { return }
                latestContent = content

                // Check for slash command trigger
                slashHandler?.contentDidChange(content: content)

                // Debounced save — capture noteID so stale saves from a previous note are dropped
                let noteID = currentNoteID
                saveDebouncer.call { [weak self] in
                    guard let self, currentNoteID == noteID else { return }
                    parent.onContentChanged(content)
                }

            case "openLink":
                guard let urlString = body["url"] as? String, !urlString.isEmpty else { return }
                // Prepend https:// if no scheme present
                let normalized = urlString.contains("://") ? urlString : "https://\(urlString)"
                guard let url = URL(string: normalized) else { return }
                NSWorkspace.shared.open(url)

            case "contextMenu":
                guard let x = body["x"] as? Double,
                      let y = body["y"] as? Double,
                      let selectedText = body["selectedText"] as? String
                else { return }
                showContextMenu(selectedText: selectedText, x: CGFloat(x), y: CGFloat(y))

            case "cursorPosition":
                guard let x = body["x"] as? Double,
                      let y = body["y"] as? Double,
                      let pos = body["pos"] as? Int
                else { return }
                slashHandler?.cursorPositionChanged(x: x, y: y, pos: pos)

            case "slashTrigger":
                // Editor detected "/" typed — show slash command popup
                guard let x = body["x"] as? Double,
                      let y = body["y"] as? Double,
                      let pos = body["pos"] as? Int
                else { return }
                slashHandler?.handleSlashTrigger(x: x, y: y, pos: pos)

            default:
                break
            }

            #if DEBUG
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                if elapsed > 5 {
                    print("[Perf] handleMessage(\(action)) took \(String(format: "%.1f", elapsed))ms")
                }
            #endif
        }

        // MARK: - Swift → JS

        func setContent(_ content: String) {
            guard let webView, isEditorReady else {
                #if DEBUG
                    print("[Editor] setContent deferred (ready=\(isEditorReady), webView=\(webView != nil))")
                #endif
                pendingContent = content
                return
            }
            let json = jsonEncode(content)
            #if DEBUG
                print("[Editor] evaluateJavaScript setContent(\(content.count) chars)")
            #endif
            webView.evaluateJavaScript("window.editorAPI.setContent(\(json))") { _, error in
                #if DEBUG
                    if let error {
                        print("[Editor] setContent JS error: \(error)")
                    }
                #endif
            }
        }

        func insertText(_ text: String) {
            guard let webView, isEditorReady else { return }
            let json = jsonEncode(text)
            webView.evaluateJavaScript("window.editorAPI.insertText(\(json))")
        }

        func focus() {
            guard let webView, isEditorReady else { return }
            webView.evaluateJavaScript("window.editorAPI.focus()")
        }

        func syncTheme() {
            guard let webView, isEditorReady else { return }
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let theme = isDark ? "dark" : "light"
            webView.evaluateJavaScript("window.editorAPI.setTheme('\(theme)')")
        }

        // MARK: - Note Navigation Shortcut (Cmd+Left/Right)

        func installNoteNavMonitor() {
            guard noteNavMonitor == nil else { return }
            noteNavMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      event.modifierFlags.contains(.command),
                      !event.modifierFlags.contains(.shift)
                else { return event }
                // Cmd+Left arrow = previous note
                if event.keyCode == 123 {
                    parent.onNavigatePrevious?()
                    return nil
                }
                // Cmd+Right arrow = next note
                if event.keyCode == 124 {
                    parent.onNavigateNext?()
                    return nil
                }
                return event
            }
        }

        func removeNoteNavMonitor() {
            if let m = noteNavMonitor {
                NSEvent.removeMonitor(m)
                noteNavMonitor = nil
            }
        }

        func getSelectedText() async -> String {
            guard let webView, isEditorReady else { return "" }
            let result = try? await webView.evaluateJavaScript("window.editorAPI.getSelectedText()")
            return (result as? String) ?? ""
        }

        // MARK: - Context Menu

        private func showContextMenu(selectedText: String, x: CGFloat, y: CGFloat) {
            guard let webView else { return }
            let l10n = L10n.shared
            let menu = NSMenu()

            menu.addActionItem(title: l10n["common.copyPlainText"], icon: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Note.plainText(from: selectedText), forType: .string)
            }
            menu.addActionItem(title: l10n["common.copyMarkdown"], icon: "doc.richtext") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(selectedText, forType: .string)
            }
            menu.addActionItem(title: l10n["common.copyRTF"], icon: "textformat") {
                let pb = NSPasteboard.general
                pb.clearContents()
                if let rtf = Note.rtfData(from: selectedText) {
                    pb.setData(rtf, forType: .rtf)
                } else {
                    pb.setString(selectedText, forType: .string)
                }
            }

            // WKWebView is flipped (isFlipped = true), so CSS clientY matches local Y directly.
            // Convert to screen coords so AppKit can flip the menu above the cursor when near
            // the bottom of the screen — same pattern as SlashCommandHandler.
            let localPoint = NSPoint(x: x, y: y)
            let windowPoint = webView.convert(localPoint, to: nil)
            let screenPoint = webView.window?.convertPoint(toScreen: windowPoint) ?? windowPoint
            menu.popUpAtScreenPoint(screenPoint)
        }

        // MARK: - Navigation Delegate

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            // The "ready" message from JS will handle initialization
        }

        // MARK: - Helpers

        private func jsonEncode(_ string: String) -> String {
            let data = try! JSONEncoder().encode(string)
            return String(data: data, encoding: .utf8)!
        }
    }
}
