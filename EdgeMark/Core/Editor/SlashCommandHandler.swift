import AppKit
import WebKit

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
    private weak var webView: WKWebView?
    private var popup: SlashCommandPopup?
    private var triggerLocation: Int?
    private var keyMonitor: Any?
    /// Last known cursor screen coordinates (from JS bridge).
    private var lastCursorX: Double = 0
    private var lastCursorY: Double = 0
    /// Last known cursor document position (from JS bridge).
    private var lastCursorPos: Int = 0
    /// Content snapshot at last change for slash filtering.
    private var lastContent: String = ""

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

    init(webView: WKWebView?) {
        self.webView = webView
    }

    // MARK: - Content Change (called from coordinator)

    func contentDidChange(content: String) {
        lastContent = content

        guard let triggerLoc = triggerLocation else {
            // Check if "/" was just typed
            checkForSlashTrigger(content: content)
            return
        }

        // Popup is active — update filter
        if lastCursorPos <= triggerLoc {
            dismiss()
            return
        }

        let start = content.index(content.startIndex, offsetBy: min(triggerLoc + 1, content.count))
        let end = content.index(content.startIndex, offsetBy: min(lastCursorPos, content.count))
        if start < end {
            let filterText = String(content[start ..< end]).lowercased()
            updateFilter(filterText)
        } else {
            popup?.updateCommands(Self.commands)
        }
    }

    func cursorPositionChanged(x: Double, y: Double, pos: Int) {
        lastCursorX = x
        lastCursorY = y
        lastCursorPos = pos
    }

    func handleSlashTrigger(x: Double, y: Double, pos: Int) {
        lastCursorX = x
        lastCursorY = y
        lastCursorPos = pos
        triggerLocation = pos - 1
        showPopup()
    }

    // MARK: - Keyboard Forwarding (called from JS key events)

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
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
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

        // Verify it's at line start or after whitespace
        if pos > 1 {
            let prevIdx = content.index(before: idx)
            let prevChar = content[prevIdx]
            guard prevChar == "\n" || prevChar == " " || prevChar == "\t" else { return }
        }

        triggerLocation = pos - 1
        showPopup()
    }

    private func showPopup() {
        guard let webView else { return }

        // JS cursor coords (from coordsAtPos) are CSS viewport-relative with Y=0 at top.
        // WKWebView is a flipped view (isFlipped=true, Y=0 at top), so its local coordinate
        // system already matches CSS coords — no manual Y-flip needed.
        // webView.convert(_:to:nil) handles the flipped→window transformation automatically.
        let localPoint = NSPoint(x: lastCursorX, y: lastCursorY)
        let windowPoint = webView.convert(localPoint, to: nil)
        let screenPoint = webView.window?.convertPoint(toScreen: windowPoint) ?? windowPoint

        popup = SlashCommandPopup(
            commands: Self.commands,
            screenOrigin: screenPoint,
            onSelect: { [weak self] command in
                self?.executeCommand(command)
            },
        )
        popup?.show(attachedTo: webView.window)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, popup != nil else { return event }
            switch event.keyCode {
            case 36: // Return
                _ = handleReturn()
                return nil
            case 125: // Arrow Down
                _ = handleArrowDown()
                return nil
            case 126: // Arrow Up
                _ = handleArrowUp()
                return nil
            case 53: // Escape
                dismiss()
                return nil
            default:
                return event
            }
        }
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
        guard let webView, let triggerLoc = triggerLocation else { return }
        let to = lastCursorPos
        let insertion = command.insertion
        let insertionJSON = jsonEncode(insertion)

        let cursorArg = if let offset = command.cursorOffset {
            ", \(triggerLoc + offset)"
        } else {
            "" // replaceRange defaults to end of insertion
        }

        let js = "window.editorAPI.replaceRange(\(triggerLoc), \(to), \(insertionJSON)\(cursorArg))"
        webView.evaluateJavaScript(js)
        dismiss()
    }

    private func jsonEncode(_ string: String) -> String {
        let data = try! JSONEncoder().encode(string)
        return String(data: data, encoding: .utf8)!
    }
}
