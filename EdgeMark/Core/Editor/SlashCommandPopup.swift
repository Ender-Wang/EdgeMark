import AppKit

final class SlashCommandPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private var panel: NSPanel?
    private var tableView: NSTableView?
    private var scrollView: NSScrollView?
    private var commands: [SlashCommand]
    private let onSelect: (SlashCommand) -> Void
    private let screenOrigin: NSPoint
    private var selectedIndex = 0

    private let rowHeight: CGFloat = 32
    private let panelWidth: CGFloat = 220
    private let maxVisibleRows = 6
    private var isAboveCursor = false

    var selectedCommand: SlashCommand? {
        guard selectedIndex >= 0, selectedIndex < commands.count else { return nil }
        return commands[selectedIndex]
    }

    init(
        commands: [SlashCommand],
        screenOrigin: NSPoint,
        onSelect: @escaping (SlashCommand) -> Void,
    ) {
        self.commands = commands
        self.screenOrigin = screenOrigin
        self.onSelect = onSelect
        super.init()
    }

    // MARK: - Show / Close

    func show(attachedTo parentWindow: NSWindow?) {
        let panelHeight = min(CGFloat(commands.count) * rowHeight + 8, CGFloat(maxVisibleRows) * rowHeight + 8)

        // Position below cursor if space allows, otherwise flip above
        let screen = parentWindow?.screen ?? NSScreen.main
        let screenMinY = screen?.visibleFrame.minY ?? 0
        let yBelow = screenOrigin.y - panelHeight - 4
        isAboveCursor = yBelow < screenMinY
        let frameY: CGFloat = isAboveCursor ? screenOrigin.y + 22 + 4 : yBelow

        let panel = NSPanel(
            contentRect: NSRect(
                x: screenOrigin.x,
                y: frameY,
                width: panelWidth,
                height: panelHeight,
            ),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.hasShadow = true

        // Container with rounded corners
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true

        // Table view
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        column.width = panelWidth - 4

        let tableView = NSTableView()
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = rowHeight
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)

        let scrollView = NSScrollView(frame: container.bounds)
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        container.addSubview(scrollView)
        panel.contentView = container

        self.panel = panel
        self.tableView = tableView
        self.scrollView = scrollView

        // Select first row
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        if let parentWindow {
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func close() {
        panel?.parent?.removeChildWindow(panel!)
        panel?.orderOut(nil)
        panel = nil
        tableView = nil
        scrollView = nil
    }

    // MARK: - Selection

    func selectNext() {
        guard !commands.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, commands.count - 1)
        tableView?.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView?.scrollRowToVisible(selectedIndex)
    }

    func selectPrevious() {
        guard !commands.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
        tableView?.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView?.scrollRowToVisible(selectedIndex)
    }

    func updateCommands(_ newCommands: [SlashCommand]) {
        commands = newCommands
        selectedIndex = 0
        tableView?.reloadData()
        if !commands.isEmpty {
            tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }

        // Resize panel
        let panelHeight = min(
            CGFloat(commands.count) * rowHeight + 8,
            CGFloat(maxVisibleRows) * rowHeight + 8,
        )
        if let panel {
            var frame = panel.frame
            let oldHeight = frame.height
            frame.size.height = panelHeight
            if !isAboveCursor {
                // Below cursor: keep top edge fixed (origin rises as height shrinks)
                frame.origin.y += oldHeight - panelHeight
            }
            // Above cursor: keep bottom edge fixed (origin.y stays, popup grows upward)
            panel.setFrame(frame, display: true)
            panel.contentView?.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in _: NSTableView) -> Int {
        commands.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard row < commands.count else { return nil }
        let command = commands[row]

        let identifier = NSUserInterfaceItemIdentifier("SlashCommandCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
            ?? NSTableCellView()
        cell.identifier = identifier

        // Remove old subviews
        cell.subviews.forEach { $0.removeFromSuperview() }

        // Icon
        let iconView = NSImageView(frame: NSRect(x: 8, y: 6, width: 20, height: 20))
        iconView.image = NSImage(systemSymbolName: command.icon, accessibilityDescription: command.title)
        iconView.contentTintColor = .secondaryLabelColor
        cell.addSubview(iconView)

        // Title
        let titleField = NSTextField(labelWithString: command.title)
        titleField.font = .systemFont(ofSize: 13)
        titleField.textColor = .labelColor
        titleField.frame = NSRect(x: 34, y: 6, width: panelWidth - 42, height: 20)
        cell.addSubview(titleField)

        return cell
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard let tableView else { return }
        selectedIndex = tableView.selectedRow
    }

    @objc private func rowDoubleClicked() {
        guard let command = selectedCommand else { return }
        onSelect(command)
    }
}
