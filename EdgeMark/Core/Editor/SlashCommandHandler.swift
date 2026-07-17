import AppKit

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
    /// Most-recently-known cursor document position (updated every content change).
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

    // MARK: - Content Change (called from MarkdownEditorView.onChange)

    func contentDidChange(content: String, cursorPos: Int) {
        lastCursorPos = cursorPos

        guard let triggerLoc = triggerLocation else {
            checkForSlashTrigger(content: content)
            return
        }

        if lastCursorPos <= triggerLoc {
            dismiss()
            return
        }

        let start = content.index(content.startIndex, offsetBy: min(triggerLoc + 1, content.count))
        let end = content.index(content.startIndex, offsetBy: min(lastCursorPos, content.count))
        if start < end {
            updateFilter(String(content[start ..< end]).lowercased())
        } else {
            popup?.updateCommands(Self.commands)
        }
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
    }

    // MARK: - Private

    private func checkForSlashTrigger(content: String) {
        let pos = lastCursorPos
        guard pos > 0, pos <= content.count else { return }
        let idx = content.index(content.startIndex, offsetBy: pos - 1)
        guard content[idx] == "/" else { return }
        if pos > 1 {
            let prevIdx = content.index(before: idx)
            let prev = content[prevIdx]
            guard prev == "\n" || prev == " " || prev == "\t" else { return }
        }
        triggerLocation = pos - 1
        showPopup()
    }

    private func showPopup() {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }

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
        guard let triggerLoc = triggerLocation else { return }
        let to = lastCursorPos
        // Dismiss before inserting — clears triggerLocation so the resulting
        // contentDidChange doesn't accidentally re-trigger slash detection.
        dismiss()
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let replaceRange = NSRange(location: triggerLoc, length: to - triggerLoc)
        textView.insertText(command.insertion, replacementRange: replaceRange)
        if let offset = command.cursorOffset {
            textView.setSelectedRange(NSRange(location: triggerLoc + offset, length: 0))
        }
    }
}
