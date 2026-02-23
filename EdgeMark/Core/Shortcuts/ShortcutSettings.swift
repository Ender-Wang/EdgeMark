import Carbon
import Foundation

// MARK: - KeyboardShortcut

struct KeyboardShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt16
    let modifiers: UInt32

    var description: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if let keyString = KeyCodeTranslator.shared.string(for: keyCode) {
            parts.append(keyString)
        }
        return parts.joined()
    }
}

// MARK: - ShortcutSettings

final class ShortcutSettings {
    static let shared = ShortcutSettings()

    var togglePanelShortcut: KeyboardShortcut? {
        didSet { save(shortcut: togglePanelShortcut, forKey: togglePanelKey) }
    }

    /// Auto-hide when the mouse exits the panel.
    var autoHideOnMouseExit: Bool {
        didSet { UserDefaults.standard.set(autoHideOnMouseExit, forKey: autoHideKey) }
    }

    /// Delay (in seconds) before auto-hiding after mouse exits. 0 = immediate.
    var hideDelay: Double {
        didSet { UserDefaults.standard.set(hideDelay, forKey: hideDelayKey) }
    }

    /// Delay (in seconds) before edge activation triggers. 0 = immediate.
    var activationDelay: Double {
        didSet { UserDefaults.standard.set(activationDelay, forKey: activationDelayKey) }
    }

    // MARK: - Keys

    private let togglePanelKey = "togglePanelShortcut"
    private let autoHideKey = "autoHideOnMouseExit"
    private let hideDelayKey = "hideDelay"
    private let activationDelayKey = "activationDelay"

    // MARK: - Init

    private init() {
        autoHideOnMouseExit = UserDefaults.standard.object(forKey: autoHideKey) as? Bool ?? true
        hideDelay = UserDefaults.standard.object(forKey: hideDelayKey) as? Double ?? 0.5
        activationDelay = UserDefaults.standard.object(forKey: activationDelayKey) as? Double ?? 0.0
        loadShortcuts()
    }

    // MARK: - Persistence

    private func loadShortcuts() {
        if let data = UserDefaults.standard.data(forKey: togglePanelKey),
           let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
        {
            togglePanelShortcut = shortcut
        } else {
            // Default: Ctrl+Shift+Space
            togglePanelShortcut = KeyboardShortcut(
                keyCode: UInt16(kVK_Space),
                modifiers: UInt32(controlKey | shiftKey),
            )
        }
    }

    private func save(shortcut: KeyboardShortcut?, forKey key: String) {
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: .shortcutSettingsChanged, object: nil)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let shortcutSettingsChanged = Notification.Name("shortcutSettingsChanged")
}
