import Carbon
import Cocoa
import Foundation
import OSLog
import ServiceManagement

// MARK: - KeyboardShortcut

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt32

    func matches(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        var required: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { required.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { required.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { required.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { required.insert(.control) }
        return event.modifierFlags.intersection([.command, .shift, .option, .control]) == required
    }

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

// MARK: - EdgeSide

enum EdgeSide: String {
    case left
    case right
}

// MARK: - AppearanceMode

enum AppearanceMode: String {
    case system
    case light
    case dark
}

// MARK: - AnimationStyle

enum AnimationStyle: String {
    /// Panel slides in/out from the screen edge (classic effect).
    /// On multi-monitor setups the slide travel may briefly appear on the adjacent display.
    case slide
    /// Panel fades in/out without any frame movement, so nothing ever appears on adjacent monitors.
    case fade
}

// MARK: - ShortcutSettings

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
            if s == shortcut { return key }
        }
        // Fixed shortcuts — always reserved; warn even if the user can't rebind them
        for (key, s) in Self.reservedShortcuts where key != ownKey {
            if s == shortcut { return key }
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

    /// Which screen edge the panel appears from.
    var edgeSide: EdgeSide {
        didSet {
            UserDefaults.standard.set(edgeSide.rawValue, forKey: edgeSideKey)
            NotificationCenter.default.post(name: .shortcutSettingsChanged, object: nil)
        }
    }

    /// Whether edge activation (mouse hover to trigger) is enabled.
    var edgeActivationEnabled: Bool {
        didSet { UserDefaults.standard.set(edgeActivationEnabled, forKey: edgeActivationEnabledKey) }
    }

    /// Whether to exclude screen corners from edge activation.
    var excludeCorners: Bool {
        didSet { UserDefaults.standard.set(excludeCorners, forKey: excludeCornersKey) }
    }

    /// Whether clicking outside the panel hides it.
    var hideOnClickOutside: Bool {
        didSet { UserDefaults.standard.set(hideOnClickOutside, forKey: hideOnClickOutsideKey) }
    }

    /// When true, the panel ignores all auto-hide triggers (mouse exit, click-outside,
    /// Space change) and stays visible until explicitly dismissed via Escape or the
    /// global toggle shortcut. Useful when copy-pasting back and forth with another app.
    var isPanelPinned: Bool {
        didSet {
            NotificationCenter.default.post(name: .panelPinStateChanged, object: nil)
        }
    }

    /// Whether swipe-right in header navigates back.
    var swipeToNavigateEnabled: Bool {
        didSet { UserDefaults.standard.set(swipeToNavigateEnabled, forKey: swipeToNavigateEnabledKey) }
    }

    /// Whether swipe left/right on editor navigates between notes.
    var editorSwipeToNavigateEnabled: Bool {
        didSet { UserDefaults.standard.set(editorSwipeToNavigateEnabled, forKey: editorSwipeToNavigateEnabledKey) }
    }

    /// Swipe sensitivity (0–1). Higher = smaller required swipe distance.
    var swipeGestureSensitivity: Double {
        didSet { UserDefaults.standard.set(swipeGestureSensitivity, forKey: swipeGestureSensitivityKey) }
    }

    /// Whether to automatically check for updates on launch (24h throttle).
    var autoCheckUpdates: Bool {
        didSet { UserDefaults.standard.set(autoCheckUpdates, forKey: autoCheckUpdatesKey) }
    }

    /// Whether the app launches at login.
    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: launchAtLoginKey)
            updateLoginItem()
        }
    }

    /// Width of the side panel in points. 400 = default minimum.
    var panelWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(panelWidth), forKey: panelWidthKey) }
    }

    /// Panel show/hide animation style.
    var animationStyle: AnimationStyle {
        didSet { UserDefaults.standard.set(animationStyle.rawValue, forKey: animationStyleKey) }
    }

    /// Appearance mode: system, light, or dark.
    var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: appearanceModeKey)
            applyAppearance()
        }
    }

    /// Custom storage directory for notes. nil = default (`~/Documents/EdgeMark/`).
    var storageDirectory: URL? {
        didSet {
            if let url = storageDirectory {
                UserDefaults.standard.set(url.path, forKey: storageDirectoryKey)
            } else {
                UserDefaults.standard.removeObject(forKey: storageDirectoryKey)
            }
            NotificationCenter.default.post(name: .shortcutSettingsChanged, object: nil)
        }
    }

    /// Resolved storage directory — custom if set, otherwise `~/Documents/EdgeMark/`.
    var resolvedStorageDirectory: URL {
        if let custom = storageDirectory {
            return custom
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("EdgeMark", isDirectory: true)
    }

    // MARK: - Keys

    private let togglePanelKey = "togglePanelShortcut"
    private let newNoteKey = "newNoteShortcut"
    private let newFolderKey = "newFolderShortcut"
    private let searchKey = "searchShortcut"
    private let pinKey = "pinShortcut"
    private let previousNoteKey = "previousNoteShortcut"
    private let nextNoteKey = "nextNoteShortcut"
    private let autoHideKey = "autoHideOnMouseExit"
    private let hideDelayKey = "hideDelay"
    private let activationDelayKey = "activationDelay"
    private let edgeSideKey = "edgeSide"
    private let edgeActivationEnabledKey = "edgeActivationEnabled"
    private let excludeCornersKey = "excludeCorners"
    private let hideOnClickOutsideKey = "hideOnClickOutside"
    private let isPanelPinnedKey = "isPanelPinned"
    private let swipeToNavigateEnabledKey = "swipeToNavigateEnabled"
    private let editorSwipeToNavigateEnabledKey = "editorSwipeToNavigateEnabled"
    private let swipeGestureSensitivityKey = "swipeGestureSensitivity"
    private let autoCheckUpdatesKey = "autoCheckUpdates"
    private let launchAtLoginKey = "launchAtLogin"
    private let storageDirectoryKey = "storageDirectory"
    private let appearanceModeKey = "appearanceMode"
    private let animationStyleKey = "animationStyle"
    private let panelWidthKey = "panelWidth"

    // MARK: - Init

    private init() {
        // Existing settings
        autoHideOnMouseExit = UserDefaults.standard.object(forKey: autoHideKey) as? Bool ?? true
        hideDelay = UserDefaults.standard.object(forKey: hideDelayKey) as? Double ?? 0.5
        activationDelay = UserDefaults.standard.object(forKey: activationDelayKey) as? Double ?? 0.0

        // New settings
        if let raw = UserDefaults.standard.string(forKey: edgeSideKey),
           let side = EdgeSide(rawValue: raw)
        {
            edgeSide = side
        } else {
            edgeSide = .right
        }
        edgeActivationEnabled = UserDefaults.standard.object(forKey: edgeActivationEnabledKey) as? Bool ?? true
        excludeCorners = UserDefaults.standard.object(forKey: excludeCornersKey) as? Bool ?? true
        hideOnClickOutside = UserDefaults.standard.object(forKey: hideOnClickOutsideKey) as? Bool ?? true
        isPanelPinned = false
        swipeToNavigateEnabled = UserDefaults.standard.object(forKey: swipeToNavigateEnabledKey) as? Bool ?? true
        editorSwipeToNavigateEnabled = UserDefaults.standard.object(forKey: editorSwipeToNavigateEnabledKey) as? Bool ?? true
        swipeGestureSensitivity = UserDefaults.standard.object(forKey: swipeGestureSensitivityKey) as? Double ?? 0.5
        autoCheckUpdates = UserDefaults.standard.object(forKey: autoCheckUpdatesKey) as? Bool ?? true
        launchAtLogin = UserDefaults.standard.object(forKey: launchAtLoginKey) as? Bool ?? false

        // Animation style
        if let raw = UserDefaults.standard.string(forKey: animationStyleKey),
           let style = AnimationStyle(rawValue: raw)
        {
            animationStyle = style
        } else {
            animationStyle = .slide
        }

        // Appearance
        if let raw = UserDefaults.standard.string(forKey: appearanceModeKey),
           let mode = AppearanceMode(rawValue: raw)
        {
            appearanceMode = mode
        } else {
            appearanceMode = .system
        }

        // Storage directory
        if let path = UserDefaults.standard.string(forKey: storageDirectoryKey) {
            storageDirectory = URL(fileURLWithPath: path, isDirectory: true)
        }

        // Panel width (stored as Double since UserDefaults doesn't have CGFloat)
        let savedWidth = UserDefaults.standard.object(forKey: panelWidthKey) as? Double
        panelWidth = savedWidth.map { CGFloat($0) } ?? 400

        loadShortcuts()
        loadLocalShortcuts()
    }

    // MARK: - Appearance

    func applyAppearance() {
        switch appearanceMode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Login Item

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let msg = error.localizedDescription
            Log.app.error("Failed to update login item: \(msg)")
        }
    }

    // MARK: - Persistence

    /// Wrapper that encodes Optional<KeyboardShortcut> so "cleared" persists
    /// across restarts. A missing UserDefaults key = "never set" (use default).
    /// A stored wrapper with shortcut = nil = "user explicitly cleared".
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
    static let shortcutSettingsChanged = Notification.Name("shortcutSettingsChanged")
    static let panelPinStateChanged = Notification.Name("panelPinStateChanged")
}
