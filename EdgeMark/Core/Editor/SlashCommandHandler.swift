import AppKit
import MarkdownEngine

struct SlashCommand: Identifiable {
    let id: String
    let title: String
    let aliases: [String]
    let icon: String
    let insertion: String
    /// Where to place the cursor relative to the start of the insertion. nil = end.
    let cursorOffset: Int?
}

final class SlashCommandHandler {
    private var popup: SlashCommandPopup?
    private var triggerLocation: Int?
    private var keyMonitor: Any?
    private weak var textView: NSTextView?
    private var lastObservedContent: String?
    /// Most-recently-known cursor document position in UTF-16 units.
    private var lastCursorPos: Int = 0

    var isActive: Bool {
        popup != nil
    }

    static var commands: [SlashCommand] {
        let l10n = L10n.shared
        return [
            SlashCommand(
                id: "h1", title: l10n["slashCmd.heading1"], aliases: ["h1", "heading"],
                icon: "textformat.size.larger", insertion: "# ", cursorOffset: nil,
            ),
            SlashCommand(
                id: "h2", title: l10n["slashCmd.heading2"], aliases: ["h2"],
                icon: "textformat.size", insertion: "## ", cursorOffset: nil,
            ),
            SlashCommand(
                id: "h3", title: l10n["slashCmd.heading3"], aliases: ["h3"],
                icon: "textformat.size.smaller", insertion: "### ", cursorOffset: nil,
            ),
            SlashCommand(
                id: "todo", title: l10n["slashCmd.taskList"], aliases: ["todo", "task", "checkbox"],
                icon: "checkmark.square", insertion: "- [ ] ", cursorOffset: nil,
            ),
            SlashCommand(
                id: "bullet", title: l10n["slashCmd.bulletList"], aliases: ["bullet", "list", "ul"],
                icon: "list.bullet", insertion: "- ", cursorOffset: nil,
            ),
            SlashCommand(
                id: "numbered", title: l10n["slashCmd.numberedList"], aliases: ["numbered", "ol", "ordered"],
                icon: "list.number", insertion: "1. ", cursorOffset: nil,
            ),
            SlashCommand(
                id: "code", title: l10n["slashCmd.codeBlock"], aliases: ["code", "codeblock"],
                icon: "chevron.left.forwardslash.chevron.right", insertion: "```\n\n```", cursorOffset: 4,
            ),
            SlashCommand(
                id: "quote", title: l10n["slashCmd.blockquote"], aliases: ["quote", "blockquote"],
                icon: "text.quote", insertion: "> ", cursorOffset: nil,
            ),
            SlashCommand(
                id: "table", title: l10n["slashCmd.table"], aliases: ["table"],
                icon: "tablecells",
                insertion: "| Column 1 | Column 2 |\n| --- | --- |\n| Cell | Cell |",
                cursorOffset: nil,
            ),
            SlashCommand(
                id: "divider", title: l10n["slashCmd.divider"], aliases: ["divider", "hr", "line"],
                icon: "minus", insertion: "\n---\n", cursorOffset: nil,
            ),
        ]
    }

    // MARK: - Text Mutation

    /// Tracks a completed native edit using the same UTF-16 coordinates as NSTextView.
    func textDidMutate(_ mutation: MarkdownTextMutation, in textView: NSTextView) {
        let currentContent = textView.string
        lastObservedContent = currentContent
        let content = currentContent as NSString
        let selection = textView.selectedRange()
        guard selection.length == 0, selection.location <= content.length else {
            dismiss()
            return
        }

        self.textView = textView
        let previousCursorPos = lastCursorPos
        lastCursorPos = selection.location

        guard let triggerLoc = triggerLocation else {
            checkForSlashTrigger(after: mutation, content: content)
            return
        }

        // An active query occupies the UTF-16 range after the slash through the
        // previous caret. Edits before the slash or outside that query invalidate
        // the session rather than trying to shift a stale replacement range.
        let queryStart = triggerLoc + 1
        guard previousCursorPos >= queryStart,
              mutation.range.location >= queryStart,
              NSMaxRange(mutation.range) <= previousCursorPos,
              mutation.range.location + mutation.replacement.utf16.count == lastCursorPos,
              lastCursorPos > triggerLoc,
              lastCursorPos <= content.length
        else {
            dismiss()
            return
        }

        let queryRange = NSRange(location: queryStart, length: lastCursorPos - queryStart)
        if queryRange.length == 0 {
            popup?.updateCommands(Self.commands)
        } else {
            updateFilter(content.substring(with: queryRange).lowercased())
        }
    }

    /// Dismisses an active session when the binding changes without a matching
    /// exact native mutation, such as an IME batch or programmatic replacement.
    func contentDidSynchronize(_ content: String) {
        guard isActive, content != lastObservedContent else { return }
        dismiss()
    }

    // MARK: - Keyboard Forwarding

    func handleArrowDown() -> Bool {
        popup?.selectNext(); return true
    }

    func handleArrowUp() -> Bool {
        popup?.selectPrevious(); return true
    }

    func handleReturn() -> Bool {
        guard let command = popup?.selectedCommand else { return false }
        executeCommand(command)
        return true
    }

    func dismiss() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor); keyMonitor = nil
        }
        popup?.close()
        popup = nil
        triggerLocation = nil
        textView = nil
        lastObservedContent = nil
    }

    // MARK: - Private

    private func checkForSlashTrigger(after mutation: MarkdownTextMutation, content: NSString) {
        let pos = lastCursorPos
        let replacementLength = mutation.replacement.utf16.count
        guard pos > 0,
              pos <= content.length,
              mutation.range.location + replacementLength == pos,
              content.character(at: pos - 1) == 0x2F
        else { return }

        if pos > 1 {
            switch content.character(at: pos - 2) {
            case 0x0A, 0x20, 0x09: break // newline, space, tab
            default: return
            }
        }
        triggerLocation = pos - 1
        guard let textView else {
            triggerLocation = nil
            return
        }
        showPopup(in: textView)
    }

    private func showPopup(in textView: NSTextView) {
        // firstRect(forCharacterRange:) returns a screen-coordinate rect for the
        // character at the cursor — use the bottom-left corner as the popup origin.
        var actualRange = NSRange()
        let cursorRect = textView.firstRect(
            forCharacterRange: textView.selectedRange(),
            actualRange: &actualRange,
        )
        let screenOrigin = NSPoint(x: cursorRect.minX, y: cursorRect.minY)

        popup = SlashCommandPopup(
            commands: Self.commands,
            screenOrigin: screenOrigin,
            onSelect: { [weak self] command in self?.executeCommand(command) },
        )
        popup?.show(attachedTo: textView.window)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, popup != nil else { return event }
            switch event.keyCode {
            case 36: _ = handleReturn(); return nil
            case 125: _ = handleArrowDown(); return nil
            case 126: _ = handleArrowUp(); return nil
            case 53: dismiss(); return nil
            default: return event
            }
        }
    }

    private func updateFilter(_ filter: String) {
        let filtered = Self.commands.filter { cmd in
            cmd.aliases.contains { $0.hasPrefix(filter) } || cmd.title.lowercased().contains(filter)
        }
        if filtered.isEmpty {
            dismiss()
        } else {
            popup?.updateCommands(filtered)
        }
    }

    // MARK: - Execution

    private func executeCommand(_ command: SlashCommand) {
        guard let triggerLoc = triggerLocation, let textView else { return }
        let to = lastCursorPos
        // Dismiss before inserting so the resulting mutation cannot extend the
        // completed slash-command session.
        dismiss()
        let replaceRange = NSRange(location: triggerLoc, length: to - triggerLoc)
        textView.insertText(command.insertion, replacementRange: replaceRange)
        if let offset = command.cursorOffset {
            textView.setSelectedRange(NSRange(location: triggerLoc + offset, length: 0))
        }
    }
}
