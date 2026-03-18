import Carbon
import Cocoa
import Foundation
import OSLog
import ServiceManagement

// MARK: - KeyboardShortcut

struct KeyboardShortcut: Codable, Equatable {
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

    /// Whether swipe-right in header navigates back.
    var swipeToNavigateEnabled: Bool {
        didSet { UserDefaults.standard.set(swipeToNavigateEnabled, forKey: swipeToNavigateEnabledKey) }
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
    private let autoHideKey = "autoHideOnMouseExit"
    private let hideDelayKey = "hideDelay"
    private let activationDelayKey = "activationDelay"
    private let edgeSideKey = "edgeSide"
    private let edgeActivationEnabledKey = "edgeActivationEnabled"
    private let excludeCornersKey = "excludeCorners"
    private let hideOnClickOutsideKey = "hideOnClickOutside"
    private let swipeToNavigateEnabledKey = "swipeToNavigateEnabled"
    private let swipeGestureSensitivityKey = "swipeGestureSensitivity"
    private let autoCheckUpdatesKey = "autoCheckUpdates"
    private let launchAtLoginKey = "launchAtLogin"
    private let storageDirectoryKey = "storageDirectory"
    private let appearanceModeKey = "appearanceMode"
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
        swipeToNavigateEnabled = UserDefaults.standard.object(forKey: swipeToNavigateEnabledKey) as? Bool ?? true
        swipeGestureSensitivity = UserDefaults.standard.object(forKey: swipeGestureSensitivityKey) as? Double ?? 0.5
        autoCheckUpdates = UserDefaults.standard.object(forKey: autoCheckUpdatesKey) as? Bool ?? true
        launchAtLogin = UserDefaults.standard.object(forKey: launchAtLoginKey) as? Bool ?? false

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

    private func loadShortcuts() {
        if let data = UserDefaults.standard.data(forKey: togglePanelKey) {
            do {
                togglePanelShortcut = try JSONDecoder().decode(KeyboardShortcut.self, from: data)
            } catch {
                Log.shortcuts.error("[ShortcutSettings] failed to decode saved shortcut — \(error), using default")
                togglePanelShortcut = KeyboardShortcut(
                    keyCode: UInt16(kVK_Space),
                    modifiers: UInt32(controlKey | shiftKey),
                )
            }
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
