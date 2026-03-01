import Cocoa
import OSLog
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panelController: SidePanelController?
    var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var updateWindowController: UpdateWindowController?

    // MARK: - Updates

    let updateState = UpdateState()

    func applicationDidFinishLaunching(_: Notification) {
        setupMenuBar()
        panelController = SidePanelController()
        panelController?.noteStore.loadFromDisk()
        ShortcutManager.shared.setup(panelController: panelController!)

        // Auto-check for updates on launch (24h throttle, respects user setting)
        if ShortcutSettings.shared.autoCheckUpdates {
            Task {
                await checkForUpdatesOnLaunch()
            }
        }
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

        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: #selector(openSettings),
            keyEquivalent: ",",
        )
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Check for Updates\u{2026}",
            action: #selector(checkForUpdates),
            keyEquivalent: "",
        ))

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

    @objc func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.show()
    }

    @objc func checkForUpdates() {
        Task {
            await performUpdateCheck(source: .manual)
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Auto-Update

    private func checkForUpdatesOnLaunch() async {
        let lastCheck = UserDefaults.standard.object(forKey: "lastUpdateCheckDate") as? Date
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 86400 {
            Log.updates.debug("[AppDelegate] update check skipped (throttled)")
            return
        }
        await performUpdateCheck(source: .launch)
    }

    func performUpdateCheck(source: UpdateState.Source) async {
        await updateState.check(source: source)

        switch source {
        case .manual:
            showUpdateResult()
        case .launch:
            if case .available = updateState.status {
                showUpdateWindow()
            }
        case .settings:
            if case .available = updateState.status {
                showUpdateWindow()
            }
        }
    }

    private func showUpdateResult() {
        switch updateState.status {
        case .available:
            showUpdateWindow()

        case .upToDate:
            let alert = NSAlert()
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            alert.messageText = "You\u{2019}re Up to Date"
            alert.informativeText = "EdgeMark v\(currentVersion) is the latest version."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()

        case let .error(error):
            let alert = NSAlert()
            alert.messageText = "Update Check Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()

        default:
            break
        }
    }

    private func showUpdateWindow() {
        guard case .available = updateState.status else { return }
        updateWindowController?.window?.close()
        updateWindowController = UpdateWindowController(updateState: updateState)
        updateWindowController?.show()
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
                options: [],
            )
            for item in contents {
                let name = item.lastPathComponent
                // Skip macOS metadata — but keep .trash/ and other app-managed hidden dirs
                if name == ".DS_Store" || name == ".localized" { continue }
                let destination = newURL.appendingPathComponent(name)
                // Skip if an item with the same name already exists at the destination
                if fm.fileExists(atPath: destination.path) { continue }
                try fm.moveItem(at: item, to: destination)
            }
        } catch {
            let msg = error.localizedDescription
            Log.storage.error("Failed to migrate storage: \(msg)")
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
