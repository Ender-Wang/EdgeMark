import Foundation
import OSLog

/// In-memory store for `.edgemark/meta.json` — the sidecar that holds all
/// note metadata previously embedded in YAML front matter.
final class SidecarStore {
    static let shared = SidecarStore()

    // MARK: - Schema

    struct NoteEntry: Codable {
        var path: String // relative to rootURL, e.g. "folder/Note.md"
        var createdAt: Date
        var modifiedAt: Date
        var savedAt: Date // last EdgeMark write — external-change sentinel
        var tags: [String] // TagColor rawValues
    }

    struct TrashEntry: Codable {
        var filename: String // bare filename inside .trash/
        var originalPath: String
        var trashedAt: Date
        var createdAt: Date
        var modifiedAt: Date
        var tags: [String]
    }

    struct FolderEntry: Codable {
        var color: String // TagColor rawValue
    }

    struct Payload: Codable {
        var version: Int = 2
        var notes: [String: NoteEntry] = [:] // UUID string → NoteEntry
        var trash: [String: TrashEntry] = [:] // UUID string → TrashEntry
        var folders: [String: FolderEntry] = [:] // folder path → FolderEntry

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            notes = try c.decodeIfPresent([String: NoteEntry].self, forKey: .notes) ?? [:]
            trash = try c.decodeIfPresent([String: TrashEntry].self, forKey: .trash) ?? [:]
            folders = try c.decodeIfPresent([String: FolderEntry].self, forKey: .folders) ?? [:]
        }

        private enum CodingKeys: String, CodingKey {
            case version, notes, trash, folders
        }
    }

    // MARK: - In-memory state

    var data = Payload()

    var sidecarURL: URL {
        FileStorage.rootURL
            .appendingPathComponent(".edgemark", isDirectory: true)
            .appendingPathComponent("meta.json")
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: sidecarURL.path)
    }

    // MARK: - Load / Save

    func load() throws {
        guard FileManager.default.fileExists(atPath: sidecarURL.path) else {
            // File not found — keep whatever is already in data (e.g. populated by migration).
            return
        }
        let raw = try Data(contentsOf: sidecarURL)
        data = try decoder.decode(Payload.self, from: raw)
        let count = data.notes.count
        Log.storage.info("[Sidecar] loaded \(count) note entries")
    }

    func save() throws {
        let dir = sidecarURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoded = try encoder.encode(data)
        try encoded.write(to: sidecarURL, options: .atomic)
    }

    // MARK: - Notes

    func noteEntry(for id: UUID) -> NoteEntry? {
        data.notes[id.uuidString]
    }

    /// Find a note entry by its relative path. O(n) but fine for typical vault sizes.
    func noteEntry(forPath path: String) -> (id: UUID, entry: NoteEntry)? {
        for (uuidStr, entry) in data.notes {
            if entry.path == path, let id = UUID(uuidString: uuidStr) {
                return (id, entry)
            }
        }
        return nil
    }

    func upsertNote(_ entry: NoteEntry, for id: UUID) {
        data.notes[id.uuidString] = entry
    }

    func removeNote(id: UUID) {
        data.notes.removeValue(forKey: id.uuidString)
    }

    // MARK: - Trash

    func trashEntry(for id: UUID) -> TrashEntry? {
        data.trash[id.uuidString]
    }

    func trashEntry(forFilename filename: String) -> (id: UUID, entry: TrashEntry)? {
        for (uuidStr, entry) in data.trash {
            if entry.filename == filename, let id = UUID(uuidString: uuidStr) {
                return (id, entry)
            }
        }
        return nil
    }

    func upsertTrash(_ entry: TrashEntry, for id: UUID) {
        data.trash[id.uuidString] = entry
    }

    func removeTrash(id: UUID) {
        data.trash.removeValue(forKey: id.uuidString)
    }

    // MARK: - Folders

    func folderEntry(forPath path: String) -> FolderEntry? {
        data.folders[path]
    }

    func upsertFolder(_ entry: FolderEntry, forPath path: String) {
        data.folders[path] = entry
    }

    func removeFolder(path: String) {
        data.folders.removeValue(forKey: path)
    }

    /// Rewrites folder entry keys after a folder rename / move. Migrates the renamed
    /// folder itself plus every nested sub-folder entry that lives under it.
    func renameFolderEntries(from oldPath: String, to newPath: String) {
        guard oldPath != newPath else { return }
        let oldPrefix = oldPath + "/"
        let newPrefix = newPath + "/"
        for key in Array(data.folders.keys) {
            if key == oldPath {
                if let entry = data.folders.removeValue(forKey: key) {
                    data.folders[newPath] = entry
                }
            } else if key.hasPrefix(oldPrefix) {
                if let entry = data.folders.removeValue(forKey: key) {
                    let newKey = newPrefix + String(key.dropFirst(oldPrefix.count))
                    data.folders[newKey] = entry
                }
            }
        }
    }

    /// Remove folder entries for a folder and all its descendants. Called on permanent delete.
    func removeFolderSubtree(path: String) {
        let prefix = path + "/"
        for key in Array(data.folders.keys) where key == path || key.hasPrefix(prefix) {
            data.folders.removeValue(forKey: key)
        }
    }

    // MARK: - Private

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
