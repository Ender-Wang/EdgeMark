import Carbon
import Cocoa
import Foundation

// MARK: - KeyboardShortcut

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt32

    func matches(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        var required: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 {
            required.insert(.command)
        }
        if modifiers & UInt32(shiftKey) != 0 {
            required.insert(.shift)
        }
        if modifiers & UInt32(optionKey) != 0 {
            required.insert(.option)
        }
        if modifiers & UInt32(controlKey) != 0 {
            required.insert(.control)
        }
        return event.modifierFlags.intersection([.command, .shift, .option, .control]) == required
    }

    var description: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }
        if let keyString = KeyCodeTranslator.shared.string(for: keyCode) {
            parts.append(keyString)
        }
        return parts.joined()
    }
}

// MARK: - ShortcutSettings

/// User-configurable keyboard shortcuts (global toggle + 6 panel-local). The app's
/// other settings domains — edge/dismissal/gestures, storage roots, appearance/updates/
/// launch — live in `PanelSettings`, `StorageSettings`, and `AppSettings` respectively.
final class ShortcutSettings {
    static let shared = ShortcutSettings()

    var togglePanelShortcut: KeyboardShortcut? {
        didSet { save(shortcut: togglePanelShortcut, forKey: togglePanelKey) }
    }

    var newNoteShortcut: KeyboardShortcut? {
        didSet { save(shortcut: newNoteShortcut, forKey: newNoteKey) }
    }

    var newFolderShortcut: KeyboardShortcut? {
        didSet { save(shortcut: newFolderShortcut, forKey: newFolderKey) }
    }

    var searchShortcut: KeyboardShortcut? {
        didSet { save(shortcut: searchShortcut, forKey: searchKey) }
    }

    var pinShortcut: KeyboardShortcut? {
        didSet { save(shortcut: pinShortcut, forKey: pinKey) }
    }

    var previousNoteShortcut: KeyboardShortcut? {
        didSet { save(shortcut: previousNoteShortcut, forKey: previousNoteKey) }
    }

    var nextNoteShortcut: KeyboardShortcut? {
        didSet { save(shortcut: nextNoteShortcut, forKey: nextNoteKey) }
    }

    // MARK: - Defaults

    static let defaultNewNote = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_N), modifiers: UInt32(cmdKey))
    static let defaultNewFolder = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_N), modifiers: UInt32(cmdKey | shiftKey))
    static let defaultSearch = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_F), modifiers: UInt32(cmdKey))
    static let defaultPin = KeyboardShortcut(keyCode: UInt16(kVK_ANSI_P), modifiers: UInt32(cmdKey))
    static let defaultPreviousNote = KeyboardShortcut(keyCode: UInt16(kVK_LeftArrow), modifiers: UInt32(cmdKey))
    static let defaultNextNote = KeyboardShortcut(keyCode: UInt16(kVK_RightArrow), modifiers: UInt32(cmdKey))

    // MARK: - Conflict detection

    /// Returns the L10n key of the shortcut that uses the same combo, or nil if no conflict.
    func conflictingKey(for shortcut: KeyboardShortcut, excluding ownKey: String) -> String? {
        // Configurable shortcuts — check live values
        let configurable: [(String, KeyboardShortcut?)] = [
            ("settings.keyboard.togglePanel", togglePanelShortcut),
            ("settings.keyboard.newNote", newNoteShortcut),
            ("settings.keyboard.newFolder", newFolderShortcut),
            ("settings.keyboard.search", searchShortcut),
            ("settings.keyboard.pinPanel", pinShortcut),
            ("settings.keyboard.previousNote", previousNoteShortcut),
            ("settings.keyboard.nextNote", nextNoteShortcut),
        ]
        for (key, s) in configurable where key != ownKey {
            if s == shortcut {
                return key
            }
        }
        // Fixed shortcuts — always reserved; warn even if the user can't rebind them
        for (key, s) in Self.reservedShortcuts where key != ownKey {
            if s == shortcut {
                return key
            }
        }
        return nil
    }

    /// Fixed shortcuts that are not user-configurable but should still produce a
    /// conflict warning when a configurable shortcut collides with them.
    private static let reservedShortcuts: [(String, KeyboardShortcut)] = [
        ("settings.keyboard.undo", KeyboardShortcut(keyCode: UInt16(kVK_ANSI_Z), modifiers: UInt32(cmdKey))),
        ("settings.keyboard.redo", KeyboardShortcut(keyCode: UInt16(kVK_ANSI_Z), modifiers: UInt32(cmdKey | shiftKey))),
        ("settings.keyboard.bold", KeyboardShortcut(keyCode: UInt16(kVK_ANSI_B), modifiers: UInt32(cmdKey))),
        ("settings.keyboard.italic", KeyboardShortcut(keyCode: UInt16(kVK_ANSI_I), modifiers: UInt32(cmdKey))),
        ("settings.keyboard.inlineCode", KeyboardShortcut(keyCode: UInt16(kVK_ANSI_E), modifiers: UInt32(cmdKey))),
        ("settings.keyboard.link", KeyboardShortcut(keyCode: UInt16(kVK_ANSI_K), modifiers: UInt32(cmdKey))),
        ("settings.keyboard.strikethrough", KeyboardShortcut(keyCode: UInt16(kVK_ANSI_X), modifiers: UInt32(cmdKey | shiftKey))),
    ]

    // MARK: - Keys

    private let togglePanelKey = "togglePanelShortcut"
    private let newNoteKey = "newNoteShortcut"
    private let newFolderKey = "newFolderShortcut"
    private let searchKey = "searchShortcut"
    private let pinKey = "pinShortcut"
    private let previousNoteKey = "previousNoteShortcut"
    private let nextNoteKey = "nextNoteShortcut"

    // MARK: - Init

    private init() {
        loadShortcuts()
        loadLocalShortcuts()
    }

    // MARK: - Persistence

    /// Wrapper that encodes Optional<KeyboardShortcut> so "cleared" persists across
    /// restarts. A missing UserDefaults key = "never set" (use default). A stored
    /// wrapper with shortcut = nil = "user explicitly cleared".
    private struct ShortcutValue: Codable {
        var shortcut: KeyboardShortcut?
    }

    private func loadShortcuts() {
        let toggleDefault = KeyboardShortcut(keyCode: UInt16(kVK_Space), modifiers: UInt32(controlKey | shiftKey))
        togglePanelShortcut = load(forKey: togglePanelKey, default: toggleDefault)
    }

    private func loadLocalShortcuts() {
        newNoteShortcut = load(forKey: newNoteKey, default: Self.defaultNewNote)
        newFolderShortcut = load(forKey: newFolderKey, default: Self.defaultNewFolder)
        searchShortcut = load(forKey: searchKey, default: Self.defaultSearch)
        pinShortcut = load(forKey: pinKey, default: Self.defaultPin)
        previousNoteShortcut = load(forKey: previousNoteKey, default: Self.defaultPreviousNote)
        nextNoteShortcut = load(forKey: nextNoteKey, default: Self.defaultNextNote)
    }

    /// Returns the saved shortcut, or `fallback` if the key was never written.
    /// Returns nil (not fallback) when the user explicitly cleared the shortcut.
    private func load(forKey key: String, default fallback: KeyboardShortcut) -> KeyboardShortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return fallback }
        // New format: ShortcutValue wrapper (nil shortcut = explicitly cleared)
        if let sv = try? JSONDecoder().decode(ShortcutValue.self, from: data) {
            return sv.shortcut
        }
        // Old format: bare KeyboardShortcut (backwards compatibility)
        return (try? JSONDecoder().decode(KeyboardShortcut.self, from: data)) ?? fallback
    }

    private func save(shortcut: KeyboardShortcut?, forKey key: String) {
        // Always write data so an explicit nil (cleared) is distinguished from
        // "never set" (absent key). Absent key = use default on next launch.
        if let data = try? JSONEncoder().encode(ShortcutValue(shortcut: shortcut)) {
            UserDefaults.standard.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: .shortcutSettingsChanged, object: nil)
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when a keyboard shortcut is rebound, and cross-posted by
    /// `PanelSettings.edgeSide`/`dismissalMode` and `StorageSettings.storageDirectory`
    /// so legacy observers (SidePanelController.handleSettingsChanged, PinButton)
    /// reconfigure. (Notification-name cleanup deferred.)
    static let shortcutSettingsChanged = Notification.Name("shortcutSettingsChanged")
}
