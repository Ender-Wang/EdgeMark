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
}
