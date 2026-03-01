import Foundation
import OSLog

enum FileStorage {
    /// Storage root — reads from ShortcutSettings so the user can configure a custom directory.
    static var rootURL: URL {
        ShortcutSettings.shared.resolvedStorageDirectory
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Directory Management

    /// Hidden `.trash/` directory at the storage root.
    static var trashURL: URL {
        rootURL.appendingPathComponent(".trash", isDirectory: true)
    }

    static func ensureRootExists() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    static func ensureTrashExists() throws {
        try FileManager.default.createDirectory(at: trashURL, withIntermediateDirectories: true)
    }

    static func ensureFolderExists(_ folderName: String) throws {
        guard !folderName.isEmpty else { return }
        let url = rootURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func renameFolder(_ oldName: String, to newName: String) throws {
        guard !oldName.isEmpty, !newName.isEmpty else { return }
        let oldURL = rootURL.appendingPathComponent(oldName, isDirectory: true)
        let newURL = rootURL.appendingPathComponent(newName, isDirectory: true)
        try FileManager.default.moveItem(at: oldURL, to: newURL)
    }

    static func deleteFolder(_ name: String) throws {
        guard !name.isEmpty else { return }
        let url = rootURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.removeItem(at: url)
    }

    static func discoverFolders() throws -> [String] {
        let fm = FileManager.default
        try ensureRootExists()
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        ) else { return [] }

        var folders: [String] = []
        let rootPath = rootURL.path
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let fullPath = url.path
                if fullPath.count > rootPath.count, fullPath.hasPrefix(rootPath) {
                    let relative = String(fullPath.dropFirst(rootPath.count + 1))
                    if !relative.isEmpty {
                        folders.append(relative)
                    }
                }
            }
        }
        let count = folders.count
        Log.storage.debug("[FileStorage] discovered \(count) folders")
        return folders.sorted()
    }

    // MARK: - Filename Helpers

    static func sanitizeForFilename(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled" }

        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\0")
        let cleaned = trimmed.unicodeScalars
            .map { illegal.contains($0) ? "-" : String($0) }
            .joined()

        let hyphenated = cleaned.replacingOccurrences(of: " ", with: "-")
        let collapsed = hyphenated.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        var result = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Truncate to stay within APFS 255-byte filename limit (.md = 3 bytes + margin)
        let maxBytes = 248
        while result.utf8.count > maxBytes {
            result = String(result.dropLast())
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return result.isEmpty ? "Untitled" : result
    }

    // MARK: - Note I/O

    static func loadAllNotes() throws -> [Note] {
        try ensureRootExists()
        var notes = try loadNotes(in: rootURL, folder: "")
        for folderName in try discoverFolders() {
            let folderURL = rootURL.appendingPathComponent(folderName, isDirectory: true)
            notes += try loadNotes(in: folderURL, folder: folderName)
        }
        let resolved = try resolveDuplicateFilenames(notes)
        let count = resolved.count
        Log.storage.info("[FileStorage] loaded \(count) notes from disk")
        return resolved
    }

    /// Writes the note to disk. If the title changed since last save, renames the old file
    /// to preserve macOS file metadata (creation date, Finder tags, extended attributes).
    /// Returns the new filename so the caller can update `savedFilename`.
    @discardableResult
    static func writeNote(_ note: Note) throws -> String {
        try ensureRootExists()
        if !note.folder.isEmpty {
            try ensureFolderExists(note.folder)
        }

        let newFilename = note.filename
        let newURL = rootURL.appendingPathComponent(note.relativePath)

        // Safety: if target file exists and isn't our own file, skip to avoid overwriting
        if let savedFilename = note.savedFilename,
           savedFilename != newFilename,
           FileManager.default.fileExists(atPath: newURL.path)
        {
            Log.storage.info("[FileStorage] filename conflict: \(newFilename, privacy: .public), keeping \(savedFilename, privacy: .public)")
            let currentRelative = note.folder.isEmpty ? savedFilename : "\(note.folder)/\(savedFilename)"
            let currentURL = rootURL.appendingPathComponent(currentRelative)
            let text = serializeFrontMatter(note: note) + note.content
            try text.data(using: .utf8)?.write(to: currentURL, options: .atomic)
            return savedFilename
        }

        // Rename old file first if title changed (preserves macOS metadata)
        if let oldFilename = note.savedFilename, oldFilename != newFilename {
            let oldRelative = note.folder.isEmpty ? oldFilename : "\(note.folder)/\(oldFilename)"
            let oldURL = rootURL.appendingPathComponent(oldRelative)
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                Log.storage.debug("[FileStorage] renamed \(oldFilename, privacy: .public) → \(newFilename, privacy: .public)")
            }
        }

        // Write content to the (possibly renamed) file
        let text = serializeFrontMatter(note: note) + note.content
        try text.data(using: .utf8)?.write(to: newURL, options: .atomic)

        return newFilename
    }

    static func deleteNote(_ note: Note) throws {
        let actualFilename = note.savedFilename ?? note.filename
        let relativePath = note.folder.isEmpty ? actualFilename : "\(note.folder)/\(actualFilename)"
        try FileManager.default.removeItem(at: rootURL.appendingPathComponent(relativePath))
    }

    /// Returns the full file URL for a note (for Finder reveal).
    static func urlForNote(_ note: Note) -> URL {
        let actualFilename = note.savedFilename ?? note.filename
        let relativePath = note.folder.isEmpty ? actualFilename : "\(note.folder)/\(actualFilename)"
        return rootURL.appendingPathComponent(relativePath)
    }

    /// Returns the full directory URL for a folder (for Finder reveal).
    static func urlForFolder(_ name: String) -> URL {
        if name.isEmpty {
            return rootURL
        }
        return rootURL.appendingPathComponent(name, isDirectory: true)
    }

    static func moveFolder(_ name: String, toParent newParent: String) throws {
        guard !name.isEmpty else { return }
        let displayName = (name as NSString).lastPathComponent
        let oldURL = rootURL.appendingPathComponent(name, isDirectory: true)
        let newFolderPath = newParent.isEmpty ? displayName : "\(newParent)/\(displayName)"
        let newURL = rootURL.appendingPathComponent(newFolderPath, isDirectory: true)
        if !newParent.isEmpty {
            try ensureFolderExists(newParent)
        }
        try FileManager.default.moveItem(at: oldURL, to: newURL)
    }

    static func moveNote(_ note: Note, toFolder: String) throws {
        let actualFilename = note.savedFilename ?? note.filename
        let oldRelative = note.folder.isEmpty ? actualFilename : "\(note.folder)/\(actualFilename)"
        let oldURL = rootURL.appendingPathComponent(oldRelative)

        if !toFolder.isEmpty {
            try ensureFolderExists(toFolder)
        }
        let newFilename = note.filename
        let newRelative = toFolder.isEmpty ? newFilename : "\(toFolder)/\(newFilename)"
        let newURL = rootURL.appendingPathComponent(newRelative)
        try FileManager.default.moveItem(at: oldURL, to: newURL)
    }

    // MARK: - Trash I/O (Individual Notes)

    /// Move a note from its current location to `.trash/<UUID>_<Title>.md`.
    /// Updates YAML to include `folder:` (return address) and `trashed:`.
    static func trashNote(_ note: Note) throws {
        try ensureTrashExists()
        let trashFilename = "\(note.id.uuidString)_\(sanitizeForFilename(note.title)).md"
        let destURL = trashURL.appendingPathComponent(trashFilename)

        // Write the trashed note (with folder + trashed fields) to .trash/
        let text = serializeFrontMatter(note: note) + note.content
        try text.data(using: .utf8)?.write(to: destURL, options: .atomic)

        // Remove original file
        let actualFilename = note.savedFilename ?? note.filename
        let oldRelative = note.folder.isEmpty ? actualFilename : "\(note.folder)/\(actualFilename)"
        try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(oldRelative))
    }

    /// Restore a note from `.trash/` back to its original folder.
    /// Returns the new `savedFilename`.
    static func restoreNote(_ note: Note) throws -> String {
        // Recreate original folder if needed
        if !note.folder.isEmpty {
            try ensureFolderExists(note.folder)
        }

        // Build a restored copy (no trashed/folder fields in YAML)
        var restored = note
        restored.trashedAt = nil

        let newFilename = restored.filename
        let destRelative = restored.folder.isEmpty ? newFilename : "\(restored.folder)/\(newFilename)"
        let destURL = rootURL.appendingPathComponent(destRelative)

        let text = serializeFrontMatter(note: restored) + restored.content
        try text.data(using: .utf8)?.write(to: destURL, options: .atomic)

        // Remove from .trash/
        if let savedFilename = note.savedFilename {
            try? FileManager.default.removeItem(at: trashURL.appendingPathComponent(savedFilename))
        }

        return newFilename
    }

    /// Delete a trashed note from `.trash/`.
    static func deleteTrashedNote(_ note: Note) throws {
        if let savedFilename = note.savedFilename {
            try FileManager.default.removeItem(at: trashURL.appendingPathComponent(savedFilename))
        }
    }

    /// Load individually trashed notes from `.trash/` (top-level `.md` files only).
    static func loadTrashedNotes() throws -> [Note] {
        try ensureTrashExists()
        let contents = try FileManager.default.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: nil,
            options: [],
        )
        let notes = contents.compactMap { url -> Note? in
            guard url.pathExtension == "md", !url.hasDirectoryPath else { return nil }
            return readNote(at: url, folder: "")
        }
        let count = notes.count
        Log.storage.debug("[FileStorage] loaded \(count) trashed notes")
        return notes
    }

    // MARK: - Trash I/O (Folders)

    /// Move a folder to `.trash/<UUID>_<DisplayName>/` and create `.folder.md` metadata.
    static func trashFolder(_ name: String, id: UUID, trashedAt: Date) throws {
        guard !name.isEmpty else { return }
        try ensureTrashExists()
        let displayName = (name as NSString).lastPathComponent
        let trashDirname = "\(id.uuidString)_\(displayName)"
        let sourceURL = rootURL.appendingPathComponent(name, isDirectory: true)
        let destURL = trashURL.appendingPathComponent(trashDirname, isDirectory: true)

        try FileManager.default.moveItem(at: sourceURL, to: destURL)

        // Write .folder.md metadata
        let folderMeta = """
        ---
        trashedAt: \(dateFormatter.string(from: trashedAt))
        originalPath: \(name)
        ---
        """
        let metaURL = destURL.appendingPathComponent(".folder.md")
        try folderMeta.data(using: .utf8)?.write(to: metaURL, options: .atomic)
    }

    /// Restore a trashed folder back to its original path.
    static func restoreFolder(_ folder: TrashedFolder) throws {
        let sourceURL = trashURL.appendingPathComponent(folder.savedDirname, isDirectory: true)

        // Remove .folder.md before moving back
        let metaURL = sourceURL.appendingPathComponent(".folder.md")
        try? FileManager.default.removeItem(at: metaURL)

        // Ensure parent directory exists
        let parentPath = (folder.originalPath as NSString).deletingLastPathComponent
        if parentPath != ".", !parentPath.isEmpty {
            try ensureFolderExists(parentPath)
        }

        let destURL = rootURL.appendingPathComponent(folder.originalPath, isDirectory: true)
        try FileManager.default.moveItem(at: sourceURL, to: destURL)
    }

    /// Permanently delete a trashed folder from `.trash/`.
    static func deleteTrashedFolder(_ folder: TrashedFolder) throws {
        let url = trashURL.appendingPathComponent(folder.savedDirname, isDirectory: true)
        try FileManager.default.removeItem(at: url)
    }

    /// Load trashed folders from `.trash/` (directories with `.folder.md` metadata).
    static func loadTrashedFolders() throws -> [TrashedFolder] {
        try ensureTrashExists()
        let contents = try FileManager.default.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
        )

        var folders: [TrashedFolder] = []
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }

            let metaURL = url.appendingPathComponent(".folder.md")
            guard let data = try? Data(contentsOf: metaURL),
                  let text = String(data: data, encoding: .utf8)
            else { continue }

            let (metadata, _) = parseFrontMatter(text)
            guard let trashedStr = metadata["trashedAt"],
                  let trashedAt = dateFormatter.date(from: trashedStr),
                  let originalPath = metadata["originalPath"]
            else { continue }

            let dirname = url.lastPathComponent
            // Parse UUID from dirname prefix (UUID_DisplayName)
            let id: UUID = if let underscoreIdx = dirname.firstIndex(of: "_"),
                              let parsed = UUID(uuidString: String(dirname[dirname.startIndex ..< underscoreIdx]))
            {
                parsed
            } else {
                UUID()
            }

            let displayName = (originalPath as NSString).lastPathComponent

            // Load all notes inside this trashed folder (recursive)
            let notes = loadNotesRecursively(in: url, baseFolder: originalPath)

            folders.append(TrashedFolder(
                id: id,
                displayName: displayName,
                originalPath: originalPath,
                trashedAt: trashedAt,
                notes: notes,
                savedDirname: dirname,
            ))
        }
        let count = folders.count
        Log.storage.debug("[FileStorage] loaded \(count) trashed folders")
        return folders
    }

    /// Recursively load notes from a directory tree (used for trashed folders).
    private static func loadNotesRecursively(in directoryURL: URL, baseFolder: String) -> [Note] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        ) else { return [] }

        var notes: [Note] = []
        let basePath = directoryURL.path
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDir, url.pathExtension == "md" {
                // Compute the folder relative to the trashed folder root
                let parentDir = url.deletingLastPathComponent().path
                let relativePart = if parentDir.count > basePath.count {
                    String(parentDir.dropFirst(basePath.count + 1))
                } else {
                    ""
                }
                let folder = relativePart.isEmpty ? baseFolder : "\(baseFolder)/\(relativePart)"
                if let note = readNote(at: url, folder: folder) {
                    notes.append(note)
                }
            }
        }
        return notes
    }

    // MARK: - Private Helpers

    private static func loadNotes(in directoryURL: URL, folder: String) throws -> [Note] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
        )
        return contents.compactMap { url -> Note? in
            guard url.pathExtension == "md" else { return nil }
            return readNote(at: url, folder: folder)
        }
    }

    private static func readNote(at url: URL, folder: String) -> Note? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        let (metadata, body) = parseFrontMatter(text)

        if metadata.isEmpty {
            // External file — no YAML front matter. Inject it using file system dates.
            let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let created = resourceValues?.creationDate ?? Date()
            let modified = resourceValues?.contentModificationDate ?? Date()
            let title = url.deletingPathExtension().lastPathComponent

            let note = Note(
                id: UUID(),
                title: title,
                content: body,
                createdAt: created,
                modifiedAt: modified,
                folder: folder,
                savedFilename: url.lastPathComponent,
            )
            let newText = serializeFrontMatter(note: note) + body
            try? newText.data(using: .utf8)?.write(to: url, options: .atomic)
            return note
        }

        let id = metadata["id"].flatMap { UUID(uuidString: $0) } ?? UUID()
        let title = metadata["title"] ?? extractTitle(from: body)
        let created = metadata["created"].flatMap { dateFormatter.date(from: $0) } ?? Date()
        let modified = metadata["modified"].flatMap { dateFormatter.date(from: $0) } ?? Date()
        let trashed = metadata["trashed"].flatMap { dateFormatter.date(from: $0) }
        // For trashed notes in .trash/, folder is stored in YAML; otherwise use the directory path.
        let resolvedFolder = metadata["folder"] ?? folder

        return Note(
            id: id,
            title: title,
            content: body,
            createdAt: created,
            modifiedAt: modified,
            folder: resolvedFolder,
            trashedAt: trashed,
            savedFilename: url.lastPathComponent,
        )
    }

    // MARK: - Front Matter

    static func parseFrontMatter(_ text: String) -> (metadata: [String: String], body: String) {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else {
            return ([:], text)
        }

        let lines = text.components(separatedBy: "\n")
        var metadata: [String: String] = [:]
        var endIndex = -1

        for i in 1 ..< lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line == "---" {
                endIndex = i
                break
            }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex ..< colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    metadata[key] = value
                }
            }
        }

        guard endIndex > 0 else { return ([:], text) }

        let bodyLines = Array(lines[(endIndex + 1)...])
        var body = bodyLines.joined(separator: "\n")
        // Strip leading newline after front matter
        if body.hasPrefix("\n") {
            body = String(body.dropFirst())
        }
        return (metadata, body)
    }

    static func serializeFrontMatter(note: Note) -> String {
        var lines = ["---"]
        lines.append("id: \(note.id.uuidString)")
        lines.append("title: \(note.title)")
        lines.append("created: \(dateFormatter.string(from: note.createdAt))")
        lines.append("modified: \(dateFormatter.string(from: note.modifiedAt))")
        if let trashedAt = note.trashedAt {
            lines.append("trashed: \(dateFormatter.string(from: trashedAt))")
            // Persist original folder as return address while in .trash/
            if !note.folder.isEmpty {
                lines.append("folder: \(note.folder)")
            }
        }
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Resolve duplicate filenames after loading. Oldest note (by createdAt) keeps its name;
    /// newer duplicates get a number suffix ("Title 2", "Title 3", etc.).
    private static func resolveDuplicateFilenames(_ notes: [Note]) throws -> [Note] {
        var groups: [String: [Int]] = [:]
        for (i, note) in notes.enumerated() {
            let key = "\(note.folder)/\(note.filename.lowercased())"
            groups[key, default: []].append(i)
        }

        var result = notes
        for (_, indices) in groups where indices.count > 1 {
            let sorted = indices.sorted { result[$0].createdAt < result[$1].createdAt }
            for duplicateIndex in sorted.dropFirst() {
                var note = result[duplicateIndex]
                let baseTitle = note.title
                var counter = 2
                var newTitle = "\(baseTitle) \(counter)"
                while result.contains(where: {
                    $0.folder == note.folder
                        && sanitizeForFilename($0.title).caseInsensitiveCompare(sanitizeForFilename(newTitle)) == .orderedSame
                }) {
                    counter += 1
                    newTitle = "\(baseTitle) \(counter)"
                }

                let oldURL = rootURL.appendingPathComponent(note.relativePath)
                Log.storage.info("[FileStorage] resolved duplicate: \(baseTitle, privacy: .public) → \(newTitle, privacy: .public)")
                note.title = newTitle
                // Update # heading in content
                var lines = note.content.components(separatedBy: "\n")
                if let headingIdx = lines.firstIndex(where: { $0.hasPrefix("#") }) {
                    let prefix = String(lines[headingIdx].prefix(while: { $0 == "#" }))
                    lines[headingIdx] = "\(prefix) \(newTitle)"
                    note.content = lines.joined(separator: "\n")
                }
                let newURL = rootURL.appendingPathComponent(note.relativePath)
                let text = serializeFrontMatter(note: note) + note.content
                try text.data(using: .utf8)?.write(to: newURL, options: .atomic)
                if oldURL != newURL {
                    try? FileManager.default.removeItem(at: oldURL)
                }
                note.savedFilename = note.filename
                result[duplicateIndex] = note
            }
        }
        return result
    }

    private static func extractTitle(from content: String) -> String {
        let firstLine = content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        // Strip leading # for markdown headings
        let stripped = firstLine.drop { $0 == "#" || $0 == " " }
        return stripped.isEmpty ? "Untitled" : String(stripped)
    }
}
