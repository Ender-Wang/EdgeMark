import Foundation

@Observable
final class AppSettings {
    // MARK: - Sort

    enum SortBy: String, CaseIterable {
        case name = "Name"
        case dateModified = "Date Modified"
        case dateCreated = "Date Created"
    }

    var sortBy: SortBy = .dateModified {
        didSet { UserDefaults.standard.set(sortBy.rawValue, forKey: "sortBy") }
    }

    var sortAscending: Bool = false {
        didSet { UserDefaults.standard.set(sortAscending, forKey: "sortAscending") }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: "sortBy"),
           let value = SortBy(rawValue: raw)
        {
            sortBy = value
        }
        sortAscending = UserDefaults.standard.bool(forKey: "sortAscending")
    }

    /// Folder date to display based on the current sort setting.
    func folderDate(for folder: Folder) -> Date? {
        switch sortBy {
        case .name: nil
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
