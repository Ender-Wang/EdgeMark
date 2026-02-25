import Cocoa
import SwiftUI

/// Shared footer bar with sort (left) and settings (right) menus.
/// Pinned at the bottom of the content card on home and folder list screens.
struct ContentFooterBar: View {
    @Environment(AppSettings.self) var settings

    var body: some View {
        HStack {
            HeaderIconButton(systemName: "arrow.up.arrow.down", help: "Sort") {
                showSortMenu()
            }
            Spacer()
            HeaderIconButton(systemName: "gearshape", help: "Settings") {
                showSettingsMenu()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    // MARK: - Sort Menu

    private func showSortMenu() {
        let menu = NSMenu()
        var actions: [MenuAction] = []

        for option in AppSettings.SortBy.allCases {
            let action = MenuAction { [settings] in settings.sortBy = option }
            actions.append(action)
            let item = NSMenuItem(
                title: option.rawValue,
                action: #selector(MenuAction.perform(_:)),
                keyEquivalent: "",
            )
            item.target = action
            item.state = settings.sortBy == option ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let dirAction = MenuAction { [settings] in settings.sortAscending.toggle() }
        actions.append(dirAction)
        let dirItem = NSMenuItem(
            title: settings.sortAscending ? "Ascending" : "Descending",
            action: #selector(MenuAction.perform(_:)),
            keyEquivalent: "",
        )
        dirItem.image = NSImage(
            systemSymbolName: settings.sortAscending ? "arrow.up" : "arrow.down",
            accessibilityDescription: nil,
        )
        dirItem.target = dirAction
        menu.addItem(dirItem)

        popUpMenu(menu, retaining: actions)
    }

    // MARK: - Settings Menu

    private func showSettingsMenu() {
        let menu = NSMenu()
        var actions: [MenuAction] = []

        let folderAction = MenuAction {
            (NSApp.delegate as? AppDelegate)?.changeNotesFolder()
        }
        actions.append(folderAction)
        let folderItem = NSMenuItem(
            title: "Change Notes Folder\u{2026}",
            action: #selector(MenuAction.perform(_:)),
            keyEquivalent: "",
        )
        folderItem.target = folderAction
        menu.addItem(folderItem)

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: nil, keyEquivalent: "")
        settingsItem.isEnabled = false
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: "Check for Updates\u{2026}", action: nil, keyEquivalent: "")
        updateItem.isEnabled = false
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitAction = MenuAction {
            NSApplication.shared.terminate(nil)
        }
        actions.append(quitAction)
        let quitItem = NSMenuItem(
            title: "Quit EdgeMark",
            action: #selector(MenuAction.perform(_:)),
            keyEquivalent: "",
        )
        quitItem.target = quitAction
        menu.addItem(quitItem)

        popUpMenu(menu, retaining: actions)
    }

    // MARK: - Helpers

    /// Show an NSMenu at the current click location.
    /// `popUpContextMenu` runs a modal tracking loop, so the `actions` array
    /// stays alive on the call stack until the menu closes.
    private func popUpMenu(_ menu: NSMenu, retaining _: [MenuAction]) {
        guard let event = NSApp.currentEvent,
              let view = event.window?.contentView
        else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}

// MARK: - MenuAction

/// Closure wrapper usable as an NSMenuItem target.
private final class MenuAction: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func perform(_: Any?) {
        handler()
    }
}
