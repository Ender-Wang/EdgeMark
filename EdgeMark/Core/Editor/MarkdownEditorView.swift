import AppKit
import SwiftUI

struct MarkdownEditorView: NSViewRepresentable {
    let noteID: UUID
    let initialContent: String
    let onContentChanged: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        // Configure for plain Markdown editing
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // Disable auto-substitution to preserve Markdown fidelity
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false

        // Comfortable insets for 400px panel
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true

        // Set initial content
        textView.string = initialContent

        // Attach coordinator
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.currentNoteID = noteID
        context.coordinator.highlighter = MarkdownHighlighter(textView: textView)
        context.coordinator.slashHandler = SlashCommandHandler(textView: textView)

        // Initial highlight
        context.coordinator.highlighter?.highlightAll()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Only update content when the note ID changes (user switched notes)
        guard context.coordinator.currentNoteID != noteID else { return }
        context.coordinator.currentNoteID = noteID

        let textView = nsView.documentView as! NSTextView
        context.coordinator.slashHandler?.dismiss()
        textView.string = initialContent
        context.coordinator.highlighter?.highlightAll()

        // Scroll to top for new note
        textView.scrollToBeginningOfDocument(nil)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: MarkdownEditorView
        weak var textView: NSTextView?
        var highlighter: MarkdownHighlighter?
        var slashHandler: SlashCommandHandler?
        var currentNoteID: UUID?
        private let saveDebouncer = Debouncer(delay: 1.0)

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
            currentNoteID = parent.noteID
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            // Re-highlight around the edit
            let editedRange = textView.selectedRange()
            highlighter?.highlightVisible(around: editedRange)

            // Check for slash command trigger
            slashHandler?.textDidChange()

            // Debounced save — skip if IME composition is active
            if !textView.hasMarkedText() {
                let content = textView.string
                saveDebouncer.call { [weak self] in
                    self?.parent.onContentChanged(content)
                }
            }
        }

        /// Forward key events to slash command popup when active
        func textView(_: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if let handler = slashHandler, handler.isActive {
                // Arrow keys, Return, Escape
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    return handler.handleArrowDown()
                } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    return handler.handleArrowUp()
                } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                    return handler.handleReturn()
                } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    handler.dismiss()
                    return true
                }
            }
            return false
        }
    }
}
