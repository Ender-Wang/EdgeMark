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
        // Shared with the live editor so previews match. `.id` rebuilds the view
        // (makeNSView) when the task-checkbox style changes — updateNSView doesn't
        // sync taskCheckbox, so only a full re-apply picks up the new symbols.
        let config = MarkdownEditorConfiguration.makeEdgeMarkConfig(noteFolder: noteFolder)
        return NativeTextViewWrapper(
            text: .constant(content),
            configuration: config,
            isEditable: false,
        )
        .id(AppSettings.shared.taskCheckboxPreset)
    }
}
