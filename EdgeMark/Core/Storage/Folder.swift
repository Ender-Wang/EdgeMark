import Foundation

struct Folder: Identifiable, Hashable {
    var id: String {
        name
    }

    let name: String
    var noteCount: Int
    var latestModifiedAt: Date?
    var earliestCreatedAt: Date?

    /// Last path component, e.g. "Projects" for "Work/Projects"
    var displayName: String {
        (name as NSString).lastPathComponent
    }

    /// Parent path, e.g. "Work" for "Work/Projects", "" for top-level
    var parentPath: String {
        let parent = (name as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }

    /// Whether this is a top-level folder (no parent)
    var isTopLevel: Bool {
        !name.contains("/")
    }
}
