import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panelController: SidePanelController?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_: Notification) {
        setupMenuBar()
        panelController = SidePanelController()
        panelController?.noteStore.loadFromDisk()
        ShortcutManager.shared.setup(panelController: panelController!)
    }

    func applicationWillTerminate(_: Notification) {
        panelController?.noteStore.saveDirtyNotes()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        panelController?.togglePanel()
        return true
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        menu.addItem(NSMenuItem(
            title: "Toggle EdgeMark",
            action: #selector(togglePanel),
            keyEquivalent: "",
        ))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Change Notes Folder\u{2026}",
            action: #selector(changeNotesFolder),
            keyEquivalent: "",
        ))

        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: #selector(openSettings),
            keyEquivalent: ",",
        )
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit EdgeMark",
            action: #selector(quitApp),
            keyEquivalent: "q",
        ))

        statusItem?.menu = menu
    }

    @objc private func togglePanel() {
        panelController?.togglePanel()
    }

    @objc func changeNotesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to store your notes"
        panel.prompt = "Select"

        // Pre-select current storage directory
        panel.directoryURL = ShortcutSettings.shared.resolvedStorageDirectory

        panel.begin { [weak self] response in
            guard response == .OK, let newURL = panel.url else { return }
            let oldURL = ShortcutSettings.shared.resolvedStorageDirectory
            guard newURL != oldURL else { return }

            // Save dirty notes to old location first
            self?.panelController?.noteStore.saveDirtyNotes()

            // Move contents from old directory to new directory
            Self.migrateStorageContents(from: oldURL, to: newURL)

            // Update the setting
            ShortcutSettings.shared.storageDirectory = newURL
            // Reload notes from the new location
            self?.panelController?.noteStore.loadFromDisk()
        }
    }

    @objc private func openSettings() {
        // Settings window comes in M3
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Storage Migration

    /// Move all files and folders from the old storage directory into the new one.
    private static func migrateStorageContents(from oldURL: URL, to newURL: URL) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: newURL, withIntermediateDirectories: true)
            let contents = try fm.contentsOfDirectory(
                at: oldURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
            )
            for item in contents {
                let destination = newURL.appendingPathComponent(item.lastPathComponent)
                // Skip if an item with the same name already exists at the destination
                if fm.fileExists(atPath: destination.path) { continue }
                try fm.moveItem(at: item, to: destination)
            }
        } catch {
            print("EdgeMark: failed to migrate storage — \(error)")
        }
    }

    // MARK: - Footer Menu Actions (reached via responder chain)

    @objc func showTrash() {
        panelController?.noteStore.showTrash = true
    }

    @objc func setSortByName() {
        panelController?.appSettings.sortBy = .name
    }

    @objc func setSortByDateModified() {
        panelController?.appSettings.sortBy = .dateModified
    }

    @objc func setSortByDateCreated() {
        panelController?.appSettings.sortBy = .dateCreated
    }

    @objc func toggleSortDirection() {
        panelController?.appSettings.sortAscending.toggle()
    }
}
