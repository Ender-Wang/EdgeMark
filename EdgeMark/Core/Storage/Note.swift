import Foundation

struct Note: Identifiable {
    let id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    var folder: String

    /// The filename currently on disk (nil for brand-new notes not yet saved).
    /// Used to detect renames when the title changes.
    var savedFilename: String?

    /// Filename derived from id + sanitized title: "UUID_Title.md"
    var filename: String {
        "\(id.uuidString)_\(FileStorage.sanitizeForFilename(title)).md"
    }

    /// Relative path from storage root: "folder/uuid_title.md" or just "uuid_title.md".
    var relativePath: String {
        folder.isEmpty ? filename : "\(folder)/\(filename)"
    }

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        folder: String = "",
        savedFilename: String? = nil,
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.folder = folder
        self.savedFilename = savedFilename
    }

    /// Compare all UI-visible properties. Exclude savedFilename (transient storage metadata).
    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.content == rhs.content
            && lhs.createdAt == rhs.createdAt
            && lhs.modifiedAt == rhs.modifiedAt
            && lhs.folder == rhs.folder
    }
}

extension Note: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
