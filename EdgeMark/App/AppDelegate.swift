import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panelController: SidePanelController?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_: Notification) {
        setupMenuBar()
        panelController = SidePanelController()
        ShortcutManager.shared.setup(panelController: panelController!)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        panelController?.togglePanel()
        return true
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "pencil.and.outline",
                accessibilityDescription: "EdgeMark",
            )
        }

        let menu = NSMenu()

        menu.addItem(NSMenuItem(
            title: "Toggle EdgeMark",
            action: #selector(togglePanel),
            keyEquivalent: "",
        ))

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
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

    @objc private func openSettings() {
        // Settings window comes in M3
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
