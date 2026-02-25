import Foundation

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

    static func ensureRootExists() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    static func ensureFolderExists(_ folderName: String) throws {
        guard !folderName.isEmpty else { return }
        let url = rootURL.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func discoverFolders() throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        )
        return contents.compactMap { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDir ? url.lastPathComponent : nil
        }.sorted()
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

        // Truncate to stay within APFS 255-byte filename limit (UUID=36 + _=1 + .md=3 = 40 overhead)
        let maxBytes = 200
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
        return notes
    }

    /// Writes the note to disk. If the title changed since last save, removes the old file.
    /// Returns the new filename so the caller can update `savedFilename`.
    @discardableResult
    static func writeNote(_ note: Note) throws -> String {
        try ensureRootExists()
        if !note.folder.isEmpty {
            try ensureFolderExists(note.folder)
        }

        let newFilename = note.filename
        let fileURL = rootURL.appendingPathComponent(note.relativePath)
        let text = serializeFrontMatter(note: note) + note.content
        try text.data(using: .utf8)?.write(to: fileURL, options: .atomic)

        // Remove old file if title changed (write-first ensures no data loss)
        if let oldFilename = note.savedFilename, oldFilename != newFilename {
            let oldRelative = note.folder.isEmpty ? oldFilename : "\(note.folder)/\(oldFilename)"
            try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(oldRelative))
        }

        return newFilename
    }

    static func deleteNote(_ note: Note) throws {
        let actualFilename = note.savedFilename ?? note.filename
        let relativePath = note.folder.isEmpty ? actualFilename : "\(note.folder)/\(actualFilename)"
        try FileManager.default.removeItem(at: rootURL.appendingPathComponent(relativePath))
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

        let id = metadata["id"].flatMap { UUID(uuidString: $0) } ?? UUID()
        let title = metadata["title"] ?? extractTitle(from: body)
        let created = metadata["created"].flatMap { dateFormatter.date(from: $0) } ?? Date()
        let modified = metadata["modified"].flatMap { dateFormatter.date(from: $0) } ?? Date()

        return Note(
            id: id,
            title: title,
            content: body,
            createdAt: created,
            modifiedAt: modified,
            folder: folder,
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
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func extractTitle(from content: String) -> String {
        let firstLine = content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        // Strip leading # for markdown headings
        let stripped = firstLine.drop { $0 == "#" || $0 == " " }
        return stripped.isEmpty ? "Untitled" : String(stripped)
    }
}
