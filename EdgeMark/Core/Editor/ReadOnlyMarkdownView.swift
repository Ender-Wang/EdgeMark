import AppKit
import SwiftUI

/// Non-editable Markdown viewer with syntax highlighting.
/// Used for previewing trashed notes.
struct ReadOnlyMarkdownView: NSViewRepresentable {
    let content: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false

        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true

        textView.string = content

        let highlighter = MarkdownHighlighter(textView: textView)
        highlighter.highlightAll()
        context.coordinator.highlighter = highlighter

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        guard textView.string != content else { return }
        textView.string = content
        context.coordinator.highlighter?.highlightAll()
        textView.scrollToBeginningOfDocument(nil)
    }

    final class Coordinator {
        var highlighter: MarkdownHighlighter?
    }
}
