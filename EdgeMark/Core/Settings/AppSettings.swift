import AppKit
import Foundation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - Sort

    enum SortBy: String, CaseIterable {
        case name = "Name"
        case dateModified = "Date Modified"
        case dateCreated = "Date Created"
    }

    // MARK: - Panel Tint

    enum PanelTint: String, CaseIterable {
        case system
        case graphite
        case slate
        case sand
        case sage
        case rose

        /// Translucent tint applied as a sublayer behind content. nil = no tint (system material only).
        var color: NSColor? {
            switch self {
            case .system: nil
            case .graphite: NSColor(white: 0.4, alpha: 0.18)
            case .slate: NSColor(red: 0.40, green: 0.50, blue: 0.62, alpha: 0.18)
            case .sand: NSColor(red: 0.80, green: 0.68, blue: 0.48, alpha: 0.18)
            case .sage: NSColor(red: 0.52, green: 0.68, blue: 0.55, alpha: 0.18)
            case .rose: NSColor(red: 0.82, green: 0.58, blue: 0.62, alpha: 0.18)
            }
        }
    }

    var sortBy: SortBy = .dateModified {
        didSet { UserDefaults.standard.set(sortBy.rawValue, forKey: "sortBy") }
    }

    var sortAscending: Bool = false {
        didSet { UserDefaults.standard.set(sortAscending, forKey: "sortAscending") }
    }

    var panelTint: PanelTint = .system {
        didSet { UserDefaults.standard.set(panelTint.rawValue, forKey: "panelTint") }
    }

    /// PostScript font name (e.g. "HelveticaNeue", "SFMono-Regular"). nil = system font.
    var editorFontName: String? {
        didSet {
            if let name = editorFontName {
                UserDefaults.standard.set(name, forKey: "editorFontName")
            } else {
                UserDefaults.standard.removeObject(forKey: "editorFontName")
            }
            NotificationCenter.default.post(name: .editorFontChanged, object: nil)
        }
    }

    /// Editor body font size in pixels. Headings scale relative to this via em units.
    var editorFontSize: Double = 16 {
        didSet {
            UserDefaults.standard.set(editorFontSize, forKey: "editorFontSize")
            NotificationCenter.default.post(name: .editorFontChanged, object: nil)
        }
    }

    // MARK: - Panel opacity

    enum PanelStyle: String, CaseIterable {
        case translucent
        case opaque

        var material: NSVisualEffectView.Material {
            switch self {
            case .translucent: .sidebar
            case .opaque: .contentBackground
            }
        }
    }

    var panelStyle: PanelStyle = .translucent {
        didSet { UserDefaults.standard.set(panelStyle.rawValue, forKey: "panelStyle") }
    }

    // MARK: - Spell checking

    /// Mirrors `SpellCheckingPolicy.continuousSpellChecking`.
    /// Default on — matches Notes / TextEdit behavior.
    var spellCheckingEnabled: Bool = true {
        didSet { UserDefaults.standard.set(spellCheckingEnabled, forKey: "spellCheckingEnabled") }
    }

    /// Mirrors `SpellCheckingPolicy.grammarChecking`.
    /// Default off — opt-in for writing-focused workflows.
    var grammarCheckingEnabled: Bool = false {
        didSet { UserDefaults.standard.set(grammarCheckingEnabled, forKey: "grammarCheckingEnabled") }
    }

    /// Mirrors `SpellCheckingPolicy.automaticSpellingCorrection`.
    /// Default off — autocorrect is disruptive in code-heavy notes.
    var automaticSpellingCorrectionEnabled: Bool = false {
        didSet { UserDefaults.standard.set(automaticSpellingCorrectionEnabled, forKey: "automaticSpellingCorrectionEnabled") }
    }

    // MARK: - Hover-to-peek

    /// Discrete dwell options for hover-to-preview. Space-to-preview is
    /// always instant (no delay) regardless of this setting.
    enum HoverPeekDelay: String, CaseIterable {
        case fast
        case normal
        case slow
        case verySlow

        var seconds: TimeInterval {
            switch self {
            case .fast: 0.15
            case .normal: 0.35
            case .slow: 0.7
            case .verySlow: 1.2
            }
        }
    }

    /// Whether hovering over a note/folder row shows a floating read-only
    /// preview on the opposite side of the panel. Default on — opt-out via
    /// the General settings tab.
    var hoverPeekEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(hoverPeekEnabled, forKey: "hoverPeekEnabled")
            NotificationCenter.default.post(name: .previewSettingsChanged, object: nil)
        }
    }

    /// Whether pressing Space on a single selected row shows the preview
    /// instantly (Quick Look behavior). Independent from hover-to-peek.
    /// Default on.
    var spaceToPreviewEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(spaceToPreviewEnabled, forKey: "spaceToPreviewEnabled")
            NotificationCenter.default.post(name: .previewSettingsChanged, object: nil)
        }
    }

    /// Hover dwell tier before the preview appears. Does not affect
    /// Space-to-preview, which is always instant.
    var hoverPeekDelay: HoverPeekDelay = .normal {
        didSet {
            UserDefaults.standard.set(hoverPeekDelay.rawValue, forKey: "hoverPeekDelay")
        }
    }

    /// Custom labels for color tags. Missing entries fall back to `TagColor.defaultLabel`.
    /// Persisted as a single UserDefaults dictionary keyed by raw color name.
    var tagLabels: [TagColor: String] = [:] {
        didSet {
            let raw = tagLabels.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value }
            UserDefaults.standard.set(raw, forKey: "tagLabels")
        }
    }

    /// Display label for a tag — user override if set, otherwise the default name.
    func label(for tag: TagColor) -> String {
        if let custom = tagLabels[tag], !custom.isEmpty {
            return custom
        }
        return tag.defaultLabel
    }

    /// Resolved NSFont for the editor — falls back to system font when no custom name is set.
    var editorFont: NSFont {
        let size = CGFloat(editorFontSize)
        if let name = editorFontName, let f = NSFont(name: name, size: size) {
            return f
        }
        return .systemFont(ofSize: size)
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: "sortBy"),
           let value = SortBy(rawValue: raw)
        {
            sortBy = value
        }
        sortAscending = UserDefaults.standard.bool(forKey: "sortAscending")
        if let raw = UserDefaults.standard.string(forKey: "panelTint"),
           let value = PanelTint(rawValue: raw)
        {
            panelTint = value
        }
        if let raw = UserDefaults.standard.string(forKey: "panelStyle"),
           let value = PanelStyle(rawValue: raw)
        {
            panelStyle = value
        }
        // If the saved font is no longer installed (e.g. user uninstalled it),
        // drop it silently so the editor falls back to the system font.
        if let saved = UserDefaults.standard.string(forKey: "editorFontName"),
           NSFont(name: saved, size: 13) != nil
        {
            editorFontName = saved
        } else {
            UserDefaults.standard.removeObject(forKey: "editorFontName")
        }
        let savedSize = UserDefaults.standard.object(forKey: "editorFontSize") as? Double
        editorFontSize = savedSize ?? 16
        if let raw = UserDefaults.standard.object(forKey: "spellCheckingEnabled") as? Bool {
            spellCheckingEnabled = raw
        }
        if let raw = UserDefaults.standard.object(forKey: "grammarCheckingEnabled") as? Bool {
            grammarCheckingEnabled = raw
        }
        if let raw = UserDefaults.standard.object(forKey: "automaticSpellingCorrectionEnabled") as? Bool {
            automaticSpellingCorrectionEnabled = raw
        }
        if let raw = UserDefaults.standard.object(forKey: "hoverPeekEnabled") as? Bool {
            hoverPeekEnabled = raw
        }
        if let raw = UserDefaults.standard.object(forKey: "spaceToPreviewEnabled") as? Bool {
            spaceToPreviewEnabled = raw
        }
        if let raw = UserDefaults.standard.string(forKey: "hoverPeekDelay"),
           let value = HoverPeekDelay(rawValue: raw)
        {
            hoverPeekDelay = value
        }
        if let raw = UserDefaults.standard.dictionary(forKey: "tagLabels") as? [String: String] {
            tagLabels = raw.reduce(into: [TagColor: String]()) { result, kv in
                if let color = TagColor(rawValue: kv.key) { result[color] = kv.value }
            }
        }
    }

    /// Folder date to display based on the current sort setting.
    func folderDate(for folder: Folder) -> Date? {
        switch sortBy {
        case .name: folder.latestModifiedAt
        case .dateModified: folder.latestModifiedAt
        case .dateCreated: folder.earliestCreatedAt
        }
    }
}

extension AppSettings.SortBy {
    func displayName(_ l10n: L10n) -> String {
        switch self {
        case .name: l10n["sort.name"]
        case .dateModified: l10n["sort.dateModified"]
        case .dateCreated: l10n["sort.dateCreated"]
        }
    }
}

extension Notification.Name {
    static let editorFontChanged = Notification.Name("editorFontChanged")
    static let previewSettingsChanged = Notification.Name("previewSettingsChanged")
}

extension AppSettings.HoverPeekDelay {
    func displayName(_ l10n: L10n) -> String {
        switch self {
        case .fast: l10n["settings.hoverDelay.fast"]
        case .normal: l10n["settings.hoverDelay.normal"]
        case .slow: l10n["settings.hoverDelay.slow"]
        case .verySlow: l10n["settings.hoverDelay.verySlow"]
        }
    }
}

extension AppSettings.PanelTint {
    func displayName(_ l10n: L10n) -> String {
        switch self {
        case .system: l10n["settings.panelTint.system"]
        case .graphite: l10n["settings.panelTint.graphite"]
        case .slate: l10n["settings.panelTint.slate"]
        case .sand: l10n["settings.panelTint.sand"]
        case .sage: l10n["settings.panelTint.sage"]
        case .rose: l10n["settings.panelTint.rose"]
        }
    }
}

extension AppSettings.PanelStyle {
    func displayName(_ l10n: L10n) -> String {
        switch self {
        case .translucent: l10n["settings.panelStyle.translucent"]
        case .opaque: l10n["settings.panelStyle.opaque"]
        }
    }
}
