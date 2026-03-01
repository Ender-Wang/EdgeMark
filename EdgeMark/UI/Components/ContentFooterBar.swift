import Cocoa
import SwiftUI

/// Shared footer bar with sort (left) and settings (right) menus.
/// Pinned at the bottom of the content card on home and folder list screens.
struct ContentFooterBar: View {
    @Environment(AppSettings.self) var settings
    @Environment(NoteStore.self) var noteStore

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
        .padding(.vertical, 6)
    }

    // MARK: - Sort Menu

    private func showSortMenu() {
        let menu = NSMenu()
        let delegate = NSApp.delegate as? AppDelegate

        for option in AppSettings.SortBy.allCases {
            let action: Selector = switch option {
            case .name: #selector(AppDelegate.setSortByName)
            case .dateModified: #selector(AppDelegate.setSortByDateModified)
            case .dateCreated: #selector(AppDelegate.setSortByDateCreated)
            }
            let item = NSMenuItem(title: option.rawValue, action: action, keyEquivalent: "")
            item.target = delegate
            item.state = settings.sortBy == option ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let dirItem = NSMenuItem(
            title: settings.sortAscending ? "Ascending" : "Descending",
            action: #selector(AppDelegate.toggleSortDirection),
            keyEquivalent: "",
        )
        dirItem.image = NSImage(
            systemSymbolName: settings.sortAscending ? "arrow.up" : "arrow.down",
            accessibilityDescription: nil,
        )
        dirItem.target = delegate
        menu.addItem(dirItem)

        popUpMenu(menu)
    }

    // MARK: - Settings Menu

    private func showSettingsMenu() {
        let menu = NSMenu()
        let delegate = NSApp.delegate as? AppDelegate

        let trashItem = NSMenuItem(
            title: "Trash",
            action: #selector(AppDelegate.showTrash),
            keyEquivalent: "",
        )
        trashItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        trashItem.target = delegate
        menu.addItem(trashItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: #selector(AppDelegate.openSettings),
            keyEquivalent: "",
        )
        settingsItem.target = delegate
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(
            title: "Check for Updates\u{2026}",
            action: #selector(AppDelegate.checkForUpdates),
            keyEquivalent: "",
        )
        updateItem.target = delegate
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit EdgeMark",
            action: #selector(AppDelegate.quitApp),
            keyEquivalent: "",
        )
        quitItem.target = delegate
        menu.addItem(quitItem)

        popUpMenu(menu)
    }

    // MARK: - Helpers

    /// Show an NSMenu at the current click location.
    private func popUpMenu(_ menu: NSMenu) {
        guard let event = NSApp.currentEvent,
              let view = event.window?.contentView
        else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}
