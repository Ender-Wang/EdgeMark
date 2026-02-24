import Foundation

struct Note: Identifiable, Hashable {
    let id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    var folder: String

    /// Filename on disk, derived from id to avoid title-collision issues.
    var filename: String {
        "\(id.uuidString).md"
    }

    /// Relative path from storage root: "folder/uuid.md" or just "uuid.md".
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
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.folder = folder
    }
}
