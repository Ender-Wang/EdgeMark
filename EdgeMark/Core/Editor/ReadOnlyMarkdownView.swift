import MarkdownEngine
import MarkdownEngineCodeBlocks
import MarkdownEngineLatex
import SwiftUI

/// Non-editable Markdown viewer using swift-markdown-engine.
/// Used for previewing trashed notes and peek previews.
struct ReadOnlyMarkdownView: View {
    let content: String
    var noteFolder: String = ""

    var body: some View {
        var config = MarkdownEditorConfiguration.default
        config.textInsets = TextInsets(horizontal: 16, vertical: 12)
        // Register highlight (==text==) and strikethrough (~~text~~). Opt-in since
        // swift-markdown-engine 0.10; without this, trashed/peeked notes render the
        // markers as literal text.
        config.extensions = [HighlightExtension(), StrikethroughExtension()]
        config.services = MarkdownEditorServices(
            images: EdgeMarkImageProvider(noteFolder: noteFolder),
            syntaxHighlighter: HighlighterSwiftBridge(),
            latex: SwiftMathBridge(),
        )
        return NativeTextViewWrapper(
            text: .constant(content),
            configuration: config,
            isEditable: false,
        )
    }
}
