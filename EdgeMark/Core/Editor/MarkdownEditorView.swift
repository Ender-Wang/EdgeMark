import AppKit
import MarkdownEngine
import MarkdownEngineCodeBlocks
import MarkdownEngineLatex
import SwiftUI

// MARK: - Image provider

/// Loads EdgeMark asset-dir images for the `![[.STEM/IMG-uuid.ext]]` embed syntax
/// used by the editor's display layer. The on-disk format stays as standard
/// `![](path)` markdown; MarkdownEditorView converts between the two transparently.
private struct EdgeMarkImageProvider: EmbeddedImageProvider {
    let noteFolder: String

    func image(for request: EmbeddedImageRequest) -> NSImage? {
        // request.name is the relative path, e.g. ".My-Note/IMG-uuid.png"
        var base = FileStorage.rootURL
        if !noteFolder.isEmpty {
            base = base.appendingPathComponent(noteFolder, isDirectory: true)
        }
        return NSImage(contentsOf: base.appendingPathComponent(request.name))
    }

    func fingerprint() -> AnyHashable {
        noteFolder
    }
}

// MARK: - MarkdownEditorView

/// SwiftUI wrapper around NativeTextViewWrapper (swift-markdown-engine).
/// Manages heading stripping, save debouncing, font observation, and the
/// slash-command popup.
struct MarkdownEditorView: View {
    let noteID: UUID
    let noteTitle: String
    let noteFolder: String
    let initialContent: String
    let onContentChanged: (String) -> Void
    /// Set to new full note content to reload the editor (e.g. from file watcher).
    /// Cleared automatically after the view applies it.
    @Binding var pendingReload: String?
    var onNavigateNext: (() -> Void)?
    var onNavigatePrevious: (() -> Void)?

    @State private var text: String
    @State private var hiddenHeadingLine: String
    @State private var saveDebouncer = Debouncer(delay: 1.0)
    @State private var slashHandler = SlashCommandHandler()
    @State private var noteNavMonitor: Any?

    init(
        noteID: UUID,
        noteTitle: String,
        noteFolder: String,
        initialContent: String,
        onContentChanged: @escaping (String) -> Void,
        pendingReload: Binding<String?> = .constant(nil),
        onNavigateNext: (() -> Void)? = nil,
        onNavigatePrevious: (() -> Void)? = nil,
    ) {
        self.noteID = noteID
        self.noteTitle = noteTitle
        self.noteFolder = noteFolder
        self.initialContent = initialContent
        self.onContentChanged = onContentChanged
        _pendingReload = pendingReload
        self.onNavigateNext = onNavigateNext
        self.onNavigatePrevious = onNavigatePrevious
        let (heading, body) = Self.splitHeading(initialContent)
        _text = State(initialValue: Self.imagesToEmbeds(body))
        _hiddenHeadingLine = State(initialValue: heading)
    }

    var body: some View {
        // Reading AppSettings.shared properties here registers @Observable tracking —
        // the view re-renders (and NativeTextViewWrapper.updateNSView re-applies font)
        // whenever editorFontName or editorFontSize changes.
        let appSettings = AppSettings.shared
        let fontName = Self.resolvedFontFamily(from: appSettings.editorFontName) ?? "SF Pro"

        var config = MarkdownEditorConfiguration.default
        config.services = MarkdownEditorServices(
            images: EdgeMarkImageProvider(noteFolder: noteFolder),
            syntaxHighlighter: HighlighterSwiftBridge(),
            latex: SwiftMathBridge(),
        )

        return NativeTextViewWrapper(
            text: $text,
            configuration: config,
            fontName: fontName,
            fontSize: CGFloat(appSettings.editorFontSize),
            documentId: noteID.uuidString,
            onPasteImage: { [noteID, noteTitle, noteFolder] pasteboard in
                guard let (data, ext) = Self.imageData(from: pasteboard) else { return nil }
                let note = Note(id: noteID, title: noteTitle, folder: noteFolder)
                // Return embed syntax — gets inserted into the display-layer text.
                // onChange converts it back to standard ![](path) markdown before saving.
                return (try? FileStorage.saveImage(data: data, ext: ext, forNote: note))?.embedMarkdown
            },
        )
        .onChange(of: text) { _, newText in
            let cursorPos = (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectedRange().location ?? 0
            slashHandler.contentDidChange(content: newText, cursorPos: cursorPos)
            let heading = hiddenHeadingLine
            saveDebouncer.call { [onContentChanged] in
                // Convert display-layer ![[path]] embeds back to on-disk ![]( path) before saving.
                let storage = Self.embedsToImages(newText)
                let full = heading.isEmpty ? storage : heading + "\n\n" + storage
                onContentChanged(full)
            }
        }
        .onChange(of: pendingReload) { _, newContent in
            guard let newContent else { return }
            saveDebouncer.cancel()
            let (heading, body) = Self.splitHeading(newContent)
            hiddenHeadingLine = heading
            text = Self.imagesToEmbeds(body)
            pendingReload = nil
        }
        .overlay(
            ImageDropOverlay { [noteID, noteTitle, noteFolder] url in
                guard let data = try? Data(contentsOf: url) else { return }
                let ext = url.pathExtension.lowercased()
                let note = Note(id: noteID, title: noteTitle, folder: noteFolder)
                guard let result = try? FileStorage.saveImage(data: data, ext: ext, forNote: note) else { return }
                // After a drag completes the text view may have lost first responder.
                // Fall back to walking the window hierarchy to find it.
                let window = NSApp.keyWindow
                let tv = (window?.firstResponder as? NSTextView)
                    ?? findEditorTextView(in: window?.contentView)
                guard let tv else { return }
                window?.makeFirstResponder(tv)
                tv.insertText(result.embedMarkdown, replacementRange: tv.selectedRange())
            },
        )
        .onAppear {
            noteNavMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
                let s = ShortcutSettings.shared
                if s.previousNoteShortcut?.matches(event) == true { onNavigatePrevious?(); return nil }
                if s.nextNoteShortcut?.matches(event) == true { onNavigateNext?(); return nil }
                return event
            }
        }
        .onDisappear {
            // Flush debounced save immediately on note switch or panel hide
            saveDebouncer.cancel()
            let storage = Self.embedsToImages(text)
            let full = hiddenHeadingLine.isEmpty ? storage : hiddenHeadingLine + "\n\n" + storage
            onContentChanged(full)
            slashHandler.dismiss()
            if let m = noteNavMonitor { NSEvent.removeMonitor(m); noteNavMonitor = nil }
        }
    }

    // MARK: - Helpers

    static func splitHeading(_ content: String) -> (heading: String, body: String) {
        let lines = content.components(separatedBy: "\n")
        guard let first = lines.first, first.hasPrefix("#") else { return ("", content) }
        var rest = Array(lines.dropFirst())
        while rest.first == "" {
            rest.removeFirst()
        }
        return (first, rest.joined(separator: "\n"))
    }

    private static func resolvedFontFamily(from postscriptName: String?) -> String? {
        guard let name = postscriptName, let font = NSFont(name: name, size: 16) else { return nil }
        return font.familyName
    }

    /// Convert on-disk `![](. STEM/IMG-uuid.ext)` references to editor embed `![[.STEM/IMG-uuid.ext]]`.
    /// Only converts EdgeMark-format images (path starts with `.`, filename starts with `IMG-`).
    static func imagesToEmbeds(_ text: String) -> String {
        guard text.contains("![") else { return text }
        let pattern = #"!\[[^\]]*\]\((\.[^/)][^)]+/IMG-[A-Za-z0-9\-]+\.[A-Za-z0-9]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
        let result = NSMutableString(string: text)
        for match in matches {
            let path = ns.substring(with: match.range(at: 1))
            result.replaceCharacters(in: match.range, with: "![[\(path)]]")
        }
        return result as String
    }

    /// Convert editor embed `![[.STEM/IMG-uuid.ext]]` back to on-disk `![](path)`.
    static func embedsToImages(_ text: String) -> String {
        guard text.contains("![[") else { return text }
        let pattern = #"!\[\[(\.[^/)][^\]]+/IMG-[A-Za-z0-9\-]+\.[A-Za-z0-9]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
        let result = NSMutableString(string: text)
        for match in matches {
            let path = ns.substring(with: match.range(at: 1))
            result.replaceCharacters(in: match.range, with: "![](\(path))")
        }
        return result as String
    }

    private static func imageData(from pasteboard: NSPasteboard) -> (Data, String)? {
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")) {
            return (data, "png")
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let img = NSImage(data: tiff),
           let rep = NSBitmapImageRep(data: img.tiffRepresentation ?? Data()),
           let png = rep.representation(using: .png, properties: [:])
        {
            return (png, "png")
        }
        return nil
    }
}
