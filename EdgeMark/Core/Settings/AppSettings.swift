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
