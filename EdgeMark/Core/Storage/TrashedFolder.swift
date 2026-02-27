import Foundation

struct TrashedFolder: Identifiable {
    /// Generated at trash time; parsed from UUID prefix in `.trash/` dirname.
    let id: UUID
    /// Last path component, e.g. "Projects".
    var displayName: String
    /// Full original path, e.g. "Work/Projects". Read from `.folder.md`.
    var originalPath: String
    var trashedAt: Date
    /// All notes inside the folder (including nested subfolders).
    var notes: [Note]
    /// Actual directory name in `.trash/`, e.g. "A1B2C3D4_Projects".
    var savedDirname: String
}

extension TrashedFolder: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TrashedFolder, rhs: TrashedFolder) -> Bool {
        lhs.id == rhs.id
    }
}
