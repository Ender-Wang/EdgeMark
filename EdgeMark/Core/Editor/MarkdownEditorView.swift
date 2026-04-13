import OSLog
import SwiftUI
import WebKit

/// WKWebView subclass that intercepts Cmd+V when the pasteboard contains an image.
/// WKWebView routes Cmd+V through `performKeyEquivalent:` directly to its web
/// process, bypassing both NSEvent local monitors and the `paste:` responder action.
/// Overriding `performKeyEquivalent:` is the only reliable interception point.
final class EditorWebView: WKWebView {
    var onImagePaste: ((Data, String) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Intercept Cmd+V only
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "v"
        {
            if let imageData = Self.imageDataFromPasteboard() {
                onImagePaste?(imageData.data, imageData.ext)
                return true // consumed — don't forward to web process
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    private static func imageDataFromPasteboard() -> (data: Data, ext: String)? {
        let pb = NSPasteboard.general
        // PNG first (CleanShot X, Cmd+Shift+4 screenshots)
        if let pngData = pb.data(forType: NSPasteboard.PasteboardType("public.png")) {
            return (pngData, "png")
        }
        // TIFF (general macOS image copy) — convert to PNG
        if let tiffData = pb.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           let tiffRep = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffRep),
           let pngData = bitmap.representation(using: .png, properties: [:])
        {
            return (pngData, "png")
        }
        return nil
    }
}

struct MarkdownEditorView: NSViewRepresentable {
    let noteID: UUID
    let noteTitle: String
    let noteFolder: String
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

        let webView = EditorWebView(frame: .zero, configuration: config)
        webView.onImagePaste = { [weak coordinator = context.coordinator] data, ext in
            coordinator?.handlePastedImageData(data, ext: ext)
        }

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
            // Grant file system root access so WKWebView can load both:
            // 1. editor.html from the app bundle (/Applications/... or ~/Library/Developer/...)
            // 2. note images from the notes directory (configurable, could be anywhere)
            // Home dir is insufficient — Homebrew installs the app in /Applications/ which
            // is outside ~/. The app runs without sandbox so root access is safe.
            webView.loadFileURL(htmlURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
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
            context.coordinator.syncNoteBaseURL()
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
        /// The leading `# Title` line stripped from content before sending to JS.
        /// Prepended back when receiving contentChanged, so storage always has the full content.
        private var hiddenHeadingLine: String = ""
        private let saveDebouncer = Debouncer(delay: 1.0)
        private let spellDebouncer = Debouncer(delay: 0.5)
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
                // Pass the note's directory URL so ImageWidget can resolve relative image paths
                syncNoteBaseURL()
                setContent(content)
                syncTheme()

                // Initialize slash handler with WKWebView bridge
                slashHandler = SlashCommandHandler(webView: webView)
                installNoteNavMonitor()

            case "contentChanged":
                guard let content = body["content"] as? String else { return }
                // Prepend hidden heading so storage always has the full content with # title
                let fullContent = hiddenHeadingLine.isEmpty ? content : hiddenHeadingLine + "\n\n" + content
                latestContent = fullContent

                // Check for slash command trigger — pass raw editor content (without heading)
                // so cursor positions from JS (which doesn't see the heading) align correctly
                slashHandler?.contentDidChange(content: content)

                // Debounced save — capture noteID so stale saves from a previous note are dropped
                let noteID = currentNoteID
                saveDebouncer.call { [weak self] in
                    guard let self, currentNoteID == noteID else { return }
                    parent.onContentChanged(fullContent)
                }

                // Debounced spell check (on the editor-visible content, not the heading)
                spellDebouncer.call { [weak self] in
                    self?.runSpellCheck(on: content)
                }

            case "saveImage":
                guard let base64 = body["data"] as? String,
                      let ext = body["ext"] as? String,
                      let data = Data(base64Encoded: base64)
                else { return }
                let note = Note(id: parent.noteID, title: parent.noteTitle, folder: parent.noteFolder)
                do {
                    let result = try FileStorage.saveImage(data: data, ext: ext, forNote: note)
                    let markdownJSON = jsonEncode(result.markdown)
                    let srcJSON = jsonEncode(result.src)
                    webView?.evaluateJavaScript(
                        "window.editorAPI.onImageSaved({ markdown: \(markdownJSON), src: \(srcJSON) })",
                    )
                } catch {
                    Log.storage.error("[Image] saveImage (drag/drop) failed: \(error)")
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
            // Strip the leading # heading line — title is shown in the header bar.
            // Store it in hiddenHeadingLine so we can prepend it back on contentChanged.
            let bodyForEditor = stripHeading(from: content)

            // Image paths stay relative (.stem/IMG-uuid.png) in the CM6 doc.
            // buildDecorations in wysiwyg.js resolves them to absolute file:// URLs
            // at render time using editorNoteBaseURL — never stored as absolute on disk.
            let json = jsonEncode(bodyForEditor)
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

        /// Strip the first `# Heading` line from content for display in the editor.
        /// Stores the line in `hiddenHeadingLine` so it can be prepended on save.
        private func stripHeading(from content: String) -> String {
            let lines = content.components(separatedBy: "\n")
            guard let first = lines.first, first.hasPrefix("#") else {
                hiddenHeadingLine = ""
                return content
            }
            hiddenHeadingLine = first
            // Drop the heading line and any immediately following blank lines
            var rest = Array(lines.dropFirst())
            while rest.first == "" {
                rest.removeFirst()
            }
            return rest.joined(separator: "\n")
        }

        func syncNoteBaseURL() {
            guard let webView, isEditorReady else { return }
            // Build the note's directory URL: storageRoot + folder/
            var baseURL = FileStorage.rootURL
            if !parent.noteFolder.isEmpty {
                baseURL = baseURL.appendingPathComponent(parent.noteFolder, isDirectory: true)
            }
            let baseJSON = jsonEncode(baseURL.absoluteString)
            webView.evaluateJavaScript("window.editorAPI.setNoteBaseURL(\(baseJSON))")
        }

        // MARK: - Spell Check

        private func runSpellCheck(on text: String) {
            let checker = NSSpellChecker.shared
            let nsText = text as NSString
            var errors: [[String: Int]] = []
            var location = 0

            while location < nsText.length {
                let misspelled = checker.checkSpelling(
                    of: text,
                    startingAt: location,
                    language: nil,
                    wrap: false,
                    inSpellDocumentWithTag: 0,
                    wordCount: nil,
                )
                guard misspelled.location != NSNotFound else { break }
                errors.append(["from": misspelled.location, "to": NSMaxRange(misspelled)])
                location = NSMaxRange(misspelled)
            }

            guard let json = try? JSONSerialization.data(withJSONObject: errors),
                  let jsonStr = String(data: json, encoding: .utf8)
            else { return }
            webView?.evaluateJavaScript("window.editorAPI.setSpellErrors(\(jsonStr))")
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

        // MARK: - Image Paste (called from EditorWebView.paste override)

        func handlePastedImageData(_ data: Data, ext: String) {
            Log.storage.info("[Image] paste intercepted — \(data.count) bytes, ext: \(ext, privacy: .public)")
            let note = Note(id: parent.noteID, title: parent.noteTitle, folder: parent.noteFolder)
            do {
                let result = try FileStorage.saveImage(data: data, ext: ext, forNote: note)
                let markdownJSON = jsonEncode(result.markdown)
                let srcJSON = jsonEncode(result.src)
                webView?.evaluateJavaScript(
                    "window.editorAPI.onImageSaved({ markdown: \(markdownJSON), src: \(srcJSON) })",
                )
            } catch {
                Log.storage.error("[Image] saveImage (paste) failed: \(error)")
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
