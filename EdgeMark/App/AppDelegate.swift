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

    @objc private func changeNotesFolder() {
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
            guard response == .OK, let url = panel.url else { return }
            // Save dirty notes to old location first
            self?.panelController?.noteStore.saveDirtyNotes()
            // Update the setting
            ShortcutSettings.shared.storageDirectory = url
            // Reload notes from the new location
            self?.panelController?.noteStore.loadFromDisk()
        }
    }

    @objc private func openSettings() {
        // Settings window comes in M3
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
