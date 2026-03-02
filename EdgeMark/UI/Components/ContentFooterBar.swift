import Cocoa
import SwiftUI

/// Shared footer bar with sort (left) and settings (right) menus.
/// Pinned at the bottom of the content card on home and folder list screens.
struct ContentFooterBar: View {
    @Environment(AppSettings.self) var settings
    @Environment(NoteStore.self) var noteStore

    var body: some View {
        let l10n = L10n.shared
        HStack {
            HeaderIconButton(systemName: "arrow.up.arrow.down", help: l10n["sort.help"]) {
                showSortMenu()
            }
            Spacer()
            HeaderIconButton(systemName: "gearshape", help: l10n["menu.settings"]) {
                showSettingsMenu()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Sort Menu

    private func showSortMenu() {
        let l10n = L10n.shared
        let menu = NSMenu()
        let delegate = NSApp.delegate as? AppDelegate

        for option in AppSettings.SortBy.allCases {
            let action: Selector = switch option {
            case .name: #selector(AppDelegate.setSortByName)
            case .dateModified: #selector(AppDelegate.setSortByDateModified)
            case .dateCreated: #selector(AppDelegate.setSortByDateCreated)
            }
            let iconName = switch option {
            case .name: "textformat"
            case .dateModified: "clock"
            case .dateCreated: "calendar"
            }
            let item = NSMenuItem(title: option.displayName(l10n), action: action, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            item.target = delegate
            item.state = settings.sortBy == option ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let dirItem = NSMenuItem(
            title: settings.sortAscending ? l10n["sort.ascending"] : l10n["sort.descending"],
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
        let l10n = L10n.shared
        let menu = NSMenu()
        let delegate = NSApp.delegate as? AppDelegate

        let trashItem = NSMenuItem(
            title: l10n["common.trash"],
            action: #selector(AppDelegate.showTrash),
            keyEquivalent: "",
        )
        trashItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        trashItem.target = delegate
        menu.addItem(trashItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: l10n["menu.settings"],
            action: #selector(AppDelegate.openSettings),
            keyEquivalent: "",
        )
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsItem.target = delegate
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(
            title: l10n["menu.checkUpdates"],
            action: #selector(AppDelegate.checkForUpdates),
            keyEquivalent: "",
        )
        updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        updateItem.target = delegate
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: l10n["menu.quit"],
            action: #selector(AppDelegate.quitApp),
            keyEquivalent: "",
        )
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
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
