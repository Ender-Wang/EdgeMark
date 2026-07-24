import Foundation

// MARK: - StorageRoot

/// A configured notes storage location. EdgeMark loads notes from exactly one root at a
/// time (the active root); `StorageRoot` is just a labeled directory the user can switch to.
/// `label` is optional — display falls back to `url.lastPathComponent` when nil.
struct StorageRoot: Codable, Hashable, Identifiable {
    /// Stable id. The migrated default root uses the fixed string "default"; user-added
    /// roots get a UUID string. Used as the `activeRootID` to track the persistent default.
    let id: String
    let url: URL
    var label: String?

    /// Display name: the user's label, or the directory's last path component if unlabeled.
    var displayName: String {
        label ?? url.lastPathComponent
    }
}

// MARK: - StorageSettings

/// Notes storage roots (#55). EdgeMark loads notes from exactly one root at a time
/// (the active root); the roots model + session override live here, split out of
/// `ShortcutSettings` so each name matches its content. All storage
/// (`FileStorage.rootURL`, `SidecarStore`, `.trash/`) resolves the active root live via
/// `resolvedStorageDirectory`. Plain class (not `@Observable`); consumers snapshot into
/// `@State` and observe `.storageRootChanged`, same pattern as `ShortcutSettings`.
final class StorageSettings {
    static let shared = StorageSettings()

    /// Legacy single-dir storage (pre-#55). nil = default. Now a fallback under the roots
    /// model — `resolvedStorageDirectory` reads it only when no active root resolves.
    /// Preserved for back-compat/migration.
    var storageDirectory: URL? {
        didSet {
            if let url = storageDirectory {
                UserDefaults.standard.set(url.path, forKey: storageDirectoryKey)
            } else {
                UserDefaults.standard.removeObject(forKey: storageDirectoryKey)
            }
            // Preserve the historical cross-post: SidePanelController.handleSettingsChanged
            // observes this to reconfigure. (Notification-name cleanup deferred.)
            NotificationCenter.default.post(name: .shortcutSettingsChanged, object: nil)
        }
    }

    /// Resolved storage directory — active storage root, else the legacy
    /// `storageDirectory`, else `~/Documents/EdgeMark/`. Authoritative from the roots
    /// model: session override (temporary switch) → persistent active root → legacy
    /// single-dir → default. Flipping the active root re-points the whole storage layer.
    var resolvedStorageDirectory: URL {
        if let root = activeStorageRoot {
            return root.url
        }
        if let custom = storageDirectory {
            return custom
        }
        return Self.defaultStorageDirectory
    }

    /// All configured storage roots. The active one is resolved by `activeRootID`,
    /// overridable at runtime by `sessionRootOverride`. See `AppDelegate.switchRoot`.
    var storageRoots: [StorageRoot] {
        didSet {
            saveStorageRoots()
            NotificationCenter.default.post(name: .storageRootChanged, object: nil)
        }
    }

    /// The persistent default root — the one EdgeMark opens with. nil falls back to the
    /// first root at resolve time. Setting persists; does NOT take effect at runtime until
    /// `switchRoot(temporary: false)` is called (which also reloads notes).
    var activeRootID: String? {
        didSet {
            if let id = activeRootID {
                UserDefaults.standard.set(id, forKey: activeRootIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeRootIDKey)
            }
            NotificationCenter.default.post(name: .storageRootChanged, object: nil)
        }
    }

    /// Opt-in: on launch with ≥2 roots, show a non-blocking picker to choose this
    /// session's root. Default off (UX continuity for existing single-root users).
    var askOnLaunch: Bool {
        didSet { UserDefaults.standard.set(askOnLaunch, forKey: askOnLaunchKey) }
    }

    /// In-memory session override — set by the menu-bar temporary switch and the
    /// ask-on-launch pick. NOT persisted; clears on restart so the app reverts to the
    /// `activeRootID` default. Takes precedence over `activeRootID` when resolving.
    var sessionRootOverride: StorageRoot? {
        didSet { NotificationCenter.default.post(name: .storageRootChanged, object: nil) }
    }

    /// The root the app currently shows: session override, else the persistent active
    /// root, else the first configured root. nil only when no roots are configured.
    var activeStorageRoot: StorageRoot? {
        if let override = sessionRootOverride {
            return override
        }
        if let id = activeRootID, let root = storageRoots.first(where: { $0.id == id }) {
            return root
        }
        return storageRoots.first
    }

    /// True when a temporary session override is active (used by the menu-bar UI to mark
    /// the switch as temporary / reverting on restart).
    var hasSessionOverride: Bool {
        sessionRootOverride != nil
    }

    static var defaultStorageDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EdgeMark", isDirectory: true)
    }

    private func saveStorageRoots() {
        if let data = try? JSONEncoder().encode(storageRoots) {
            UserDefaults.standard.set(data, forKey: storageRootsKey)
        }
    }

    // MARK: - Keys

    private let storageDirectoryKey = "storageDirectory"
    private let storageRootsKey = "storageRoots"
    private let activeRootIDKey = "activeRootID"
    private let askOnLaunchKey = "askOnLaunch"

    // MARK: - Init

    private init() {
        // Legacy storage directory
        if let path = UserDefaults.standard.string(forKey: storageDirectoryKey) {
            storageDirectory = URL(fileURLWithPath: path, isDirectory: true)
        }

        // Roots model
        if let data = UserDefaults.standard.data(forKey: storageRootsKey),
           let roots = try? JSONDecoder().decode([StorageRoot].self, from: data)
        {
            storageRoots = roots
        } else {
            storageRoots = []
        }
        activeRootID = UserDefaults.standard.string(forKey: activeRootIDKey)
        askOnLaunch = UserDefaults.standard.object(forKey: askOnLaunchKey) as? Bool ?? false
        sessionRootOverride = nil

        // Migration: seed one root from the legacy `storageDirectory` (or the default
        // path) the first time the roots model runs, so existing users keep their current
        // storage location as a labeled "Default" root. Property observers don't fire
        // during init, so persist explicitly.
        if storageRoots.isEmpty {
            let seedURL = storageDirectory ?? Self.defaultStorageDirectory
            storageRoots = [StorageRoot(id: "default", url: seedURL, label: "Default")]
            if activeRootID == nil {
                activeRootID = "default"
            }
            saveStorageRoots()
            if let id = activeRootID {
                UserDefaults.standard.set(id, forKey: activeRootIDKey)
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when the active storage root changes (switch, settings edit, or session
    /// override). Distinct from `shortcutSettingsChanged` so note-list reload and the
    /// switcher UI can react cleanly.
    static let storageRootChanged = Notification.Name("storageRootChanged")
}
