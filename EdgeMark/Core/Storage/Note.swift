import Foundation

struct Note: Identifiable {
    let id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    var folder: String

    /// When the note was moved to Trash (nil = active). Persisted in YAML front matter.
    var trashedAt: Date?

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

    /// User-facing display path without the UUID prefix: "folder/title.md" or "title.md".
    var displayPath: String {
        let displayName = "\(FileStorage.sanitizeForFilename(title)).md"
        return folder.isEmpty ? displayName : "\(folder)/\(displayName)"
    }

    /// Directory portion only: "/FolderName/" or "/" for root notes.
    var displayDirectory: String {
        folder.isEmpty ? "/" : "/\(folder)/"
    }

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        folder: String = "",
        trashedAt: Date? = nil,
        savedFilename: String? = nil,
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.folder = folder
        self.trashedAt = trashedAt
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
            && lhs.trashedAt == rhs.trashedAt
    }
}

extension Note: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
