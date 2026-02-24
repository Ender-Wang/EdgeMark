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
    private weak var textView: NSTextView?
    private var popup: SlashCommandPopup?
    private var triggerLocation: Int?

    var isActive: Bool {
        popup != nil
    }

    static let commands: [SlashCommand] = [
        SlashCommand(
            id: "h1", title: "Heading 1", aliases: ["h1", "heading"],
            icon: "textformat.size.larger", insertion: "# ", cursorOffset: nil,
        ),
        SlashCommand(
            id: "h2", title: "Heading 2", aliases: ["h2"],
            icon: "textformat.size", insertion: "## ", cursorOffset: nil,
        ),
        SlashCommand(
            id: "h3", title: "Heading 3", aliases: ["h3"],
            icon: "textformat.size.smaller", insertion: "### ", cursorOffset: nil,
        ),
        SlashCommand(
            id: "todo", title: "Task List", aliases: ["todo", "task", "checkbox"],
            icon: "checkmark.square", insertion: "- [ ] ", cursorOffset: nil,
        ),
        SlashCommand(
            id: "bullet", title: "Bullet List", aliases: ["bullet", "list", "ul"],
            icon: "list.bullet", insertion: "- ", cursorOffset: nil,
        ),
        SlashCommand(
            id: "numbered", title: "Numbered List", aliases: ["numbered", "ol", "ordered"],
            icon: "list.number", insertion: "1. ", cursorOffset: nil,
        ),
        SlashCommand(
            id: "code", title: "Code Block", aliases: ["code", "codeblock"],
            icon: "chevron.left.forwardslash.chevron.right", insertion: "```\n\n```", cursorOffset: 4,
        ),
        SlashCommand(
            id: "quote", title: "Blockquote", aliases: ["quote", "blockquote"],
            icon: "text.quote", insertion: "> ", cursorOffset: nil,
        ),
        SlashCommand(
            id: "table", title: "Table", aliases: ["table"],
            icon: "tablecells",
            insertion: "| Column 1 | Column 2 |\n| --- | --- |\n| Cell | Cell |",
            cursorOffset: nil,
        ),
        SlashCommand(
            id: "divider", title: "Divider", aliases: ["divider", "hr", "line"],
            icon: "minus", insertion: "\n---\n", cursorOffset: nil,
        ),
    ]

    init(textView: NSTextView) {
        self.textView = textView
    }

    // MARK: - Trigger Detection

    func textDidChange() {
        guard let textView else { return }
        let nsString = textView.string as NSString
        let cursorLocation = textView.selectedRange().location

        // If popup is showing, update filter
        if let triggerLoc = triggerLocation {
            if cursorLocation <= triggerLoc {
                dismiss()
                return
            }
            let filterRange = NSRange(location: triggerLoc + 1, length: cursorLocation - triggerLoc - 1)
            if filterRange.length > 0 {
                let filterText = nsString.substring(with: filterRange).lowercased()
                updateFilter(filterText)
            } else {
                popup?.updateCommands(Self.commands)
            }
            return
        }

        // Check if "/" was just typed
        guard cursorLocation > 0 else { return }
        let charIndex = cursorLocation - 1
        let char = nsString.character(at: charIndex)
        guard char == 0x2F /* "/" */ else { return }

        // Verify it's at line start or after whitespace
        if charIndex > 0 {
            let prevChar = nsString.character(at: charIndex - 1)
            guard let prevScalar = Unicode.Scalar(prevChar),
                  CharacterSet.whitespacesAndNewlines.contains(prevScalar)
            else { return }
        }

        triggerLocation = charIndex
        showPopup()
    }

    // MARK: - Keyboard Forwarding

    func handleArrowDown() -> Bool {
        popup?.selectNext()
        return true
    }

    func handleArrowUp() -> Bool {
        popup?.selectPrevious()
        return true
    }

    func handleReturn() -> Bool {
        guard let command = popup?.selectedCommand else { return false }
        executeCommand(command)
        return true
    }

    func dismiss() {
        popup?.close()
        popup = nil
        triggerLocation = nil
    }

    // MARK: - Popup

    private func showPopup() {
        guard let textView else { return }
        let cursorLoc = textView.selectedRange().location
        var actualRange = NSRange()
        let screenRect = textView.firstRect(
            forCharacterRange: NSRange(location: cursorLoc, length: 0),
            actualRange: &actualRange,
        )

        popup = SlashCommandPopup(
            commands: Self.commands,
            screenOrigin: NSPoint(x: screenRect.origin.x, y: screenRect.origin.y),
            onSelect: { [weak self] command in
                self?.executeCommand(command)
            },
        )
        popup?.show(attachedTo: textView.window)
    }

    private func updateFilter(_ filter: String) {
        let filtered = Self.commands.filter { cmd in
            cmd.aliases.contains { $0.hasPrefix(filter) }
                || cmd.title.lowercased().contains(filter)
        }
        if filtered.isEmpty {
            dismiss()
        } else {
            popup?.updateCommands(filtered)
        }
    }

    // MARK: - Execution

    private func executeCommand(_ command: SlashCommand) {
        guard let textView, let triggerLoc = triggerLocation else { return }
        let cursorLoc = textView.selectedRange().location
        let replaceRange = NSRange(location: triggerLoc, length: cursorLoc - triggerLoc)

        textView.insertText(command.insertion, replacementRange: replaceRange)

        // Position cursor if specified
        if let offset = command.cursorOffset {
            let newPos = triggerLoc + offset
            textView.setSelectedRange(NSRange(location: newPos, length: 0))
        }

        dismiss()
    }
}
