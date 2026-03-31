import Cocoa
import OSLog
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panelController: SidePanelController?
    var statusItem: NSStatusItem?
    private var updateWindowController: UpdateWindowController?
    private var localeObserver: Any?
    private var updateTimer: Timer?

    // MARK: - Updates

    let updateState = UpdateState()

    func applicationDidFinishLaunching(_: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        Log.app.info("[AppDelegate] launched v\(version, privacy: .public) (build \(build, privacy: .public))")
        ShortcutSettings.shared.applyAppearance()
        setupMenuBar()
        panelController = SidePanelController()
        panelController?.noteStore.loadFromDisk()
        ShortcutManager.shared.setup(panelController: panelController!)

        // Rebuild menu bar when locale changes
        localeObserver = NotificationCenter.default.addObserver(
            forName: .localeDidChange,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            self?.setupMenuBar()
        }

        // Auto-check for updates on launch (24h throttle, respects user setting)
        if ShortcutSettings.shared.autoCheckUpdates {
            Task {
                await checkForUpdatesOnLaunch()
            }
            scheduleBackgroundUpdateCheck()
        }

        // Request notification permission for background update alerts
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationWillTerminate(_: Notification) {
        Log.app.info("[AppDelegate] terminating")
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

        let l10n = L10n.shared
        let menu = NSMenu()

        menu.addItem(NSMenuItem(
            title: l10n["menu.toggle"],
            action: #selector(togglePanel),
            keyEquivalent: "",
        ))

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: l10n["menu.settings"],
            action: #selector(openSettings),
            keyEquivalent: "",
        )
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: l10n["menu.checkUpdates"],
            action: #selector(checkForUpdates),
            keyEquivalent: "",
        ))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: l10n["menu.quit"],
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
        panel.message = L10n.shared["settings.general.chooseFolderMessage"]
        panel.prompt = L10n.shared["common.select"]

        // Pre-select current storage directory
        panel.directoryURL = ShortcutSettings.shared.resolvedStorageDirectory

        panel.begin { [weak self] response in
            guard response == .OK, let newURL = panel.url else { return }
            let oldURL = ShortcutSettings.shared.resolvedStorageDirectory
            guard newURL != oldURL else { return }

            // Save dirty notes to old location first
            self?.panelController?.noteStore.saveDirtyNotes()

            // Move contents from old directory to new directory
            Log.app.info("[AppDelegate] migrating storage to \(newURL.path, privacy: .public)")
            Self.migrateStorageContents(from: oldURL, to: newURL)

            // Update the setting
            ShortcutSettings.shared.storageDirectory = newURL
            // Reload notes from the new location
            self?.panelController?.noteStore.loadFromDisk()
            Log.app.info("[AppDelegate] migration complete")
        }
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        EnvironmentValues().openSettings()
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

    /// Schedule a repeating background update check. Uses a random initial delay (1–6 hours)
    /// so the check time naturally varies day-to-day for users with fixed routines.
    private func scheduleBackgroundUpdateCheck() {
        let initialDelay = Double.random(in: 3600 ... 21600) // 1–6 hours
        Log.updates.debug("[AppDelegate] background update check scheduled in \(Int(initialDelay / 60))m")
        updateTimer = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { [weak self] _ in
            self?.fireBackgroundCheck()
            // After first fire, repeat every 24 hours
            self?.updateTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
                self?.fireBackgroundCheck()
            }
        }
    }

    private func fireBackgroundCheck() {
        guard ShortcutSettings.shared.autoCheckUpdates else { return }
        Task {
            await updateState.check(source: .launch)
            if case let .available(release) = updateState.status {
                sendUpdateNotification(version: release.version)
            }
        }
    }

    private func sendUpdateNotification(version: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.shared["updates.available.title"]
        content.body = L10n.shared.t("updates.available.notification", version)
        content.sound = .default

        let request = UNNotificationRequest(identifier: "edgemark-update", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
            alert.messageText = L10n.shared["updates.upToDate.title"]
            alert.informativeText = L10n.shared.t("updates.upToDate.message", currentVersion)
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.shared["common.ok"])
            alert.runModal()

        case let .error(error):
            let alert = NSAlert()
            alert.messageText = L10n.shared["updates.checkFailed"]
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.shared["common.ok"])
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
        panelController?.noteStore.openTrash()
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

// MARK: - Notification Delegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show notification even when app is in foreground (menu bar app is always "foreground").
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner, .sound])
    }

    /// User tapped the notification — open the update window.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive _: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        showUpdateWindow()
        completionHandler()
    }
}
