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

    // MARK: - External Change Detection

    /// Resolves the actual path of a note on disk, preferring `savedFilename` over the
    /// title-derived `filename` to handle any sanitization edge cases.
    private static func diskRelativePath(for note: Note) -> String {
        let filename = note.savedFilename ?? note.filename
        return note.folder.isEmpty ? filename : "\(note.folder)/\(filename)"
    }

    /// Returns the filesystem modification date of a note's file, or nil if the file doesn't exist.
    static func modificationDate(for note: Note) -> Date? {
        let url = rootURL.appendingPathComponent(diskRelativePath(for: note))
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Reloads a note's content + tags from disk after an external change is detected.
    static func reloadContent(for note: Note) -> (content: String, modifiedAt: Date, savedAt: Date, tags: [TagColor])? {
        let url = rootURL.appendingPathComponent(diskRelativePath(for: note))
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let diskDate = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? Date()

        // Body may still have YAML if this note wasn't migrated yet — strip it.
        let (metadata, body) = parseFrontMatter(text)
        let content = metadata.isEmpty ? text : body

        let tags: [TagColor] = if let entry = SidecarStore.shared.noteEntry(for: note.id) {
            entry.tags.compactMap { TagColor(rawValue: $0) }
        } else {
            parseTagList(metadata["tags"] ?? "")
        }
        // After an external edit, savedAt should advance to the new disk date so the
        // watcher doesn't fire again for the same change.
        return (content: content, modifiedAt: diskDate, savedAt: diskDate, tags: tags)
    }

    // MARK: - Asset Directory

    /// Hidden dot-prefix asset directory co-located with a note file.
    /// e.g. "My-Note.md" → ".My-Note/" in the same parent directory.
    /// stem = sanitized filename WITHOUT the .md extension.
    static func assetDirURL(stem: String, folder: String, inTrash: Bool = false) -> URL {
        let base = inTrash ? trashURL : rootURL
        let dirName = "." + stem
        if !inTrash, !folder.isEmpty {
            return base.appendingPathComponent(folder, isDirectory: true)
                .appendingPathComponent(dirName, isDirectory: true)
        }
        return base.appendingPathComponent(dirName, isDirectory: true)
    }

    /// Save image data to the note's asset directory.
    /// Returns both the on-disk storage markdown `![](path)` and the embed syntax `![[path]]`
    /// used by the editor's display layer.
    static func saveImage(data: Data, ext: String, forNote note: Note) throws -> (markdown: String, embedMarkdown: String, src: String) {
        let stem = sanitizeForFilename(note.title)
        let assetDir = assetDirURL(stem: stem, folder: note.folder)
        try FileManager.default.createDirectory(at: assetDir, withIntermediateDirectories: true)
        let imageFilename = "IMG-\(UUID().uuidString).\(ext)"
        let destURL = assetDir.appendingPathComponent(imageFilename)
        try data.write(to: destURL, options: .atomic)
        Log.storage.info("[Image] saved \(imageFilename, privacy: .public) (\(data.count) bytes) for '\(note.title, privacy: .public)'")
        let path = "." + stem + "/" + imageFilename
        return (
            markdown: "![](\(path))",
            embedMarkdown: "![[\(path)]]",
            src: destURL.absoluteString,
        )
    }

    /// Remove image files in the asset dir that are no longer referenced in the note body.
    /// Also removes the asset dir itself if it becomes empty.
    static func cleanOrphanedImages(forNote note: Note, body: String) {
        let stem = sanitizeForFilename(note.title)
        let assetDir = assetDirURL(stem: stem, folder: note.folder)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: assetDir, includingPropertiesForKeys: nil,
        ) else { return }
        var removed = 0
        for file in files where !body.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
            removed += 1
        }
        if removed > 0 {
            Log.storage.debug("[Image] cleaned \(removed) orphaned image(s) from '\(note.title, privacy: .public)'")
        }
        if removed == files.count {
            try? FileManager.default.removeItem(at: assetDir)
            Log.storage.debug("[Image] removed empty asset dir for '\(note.title, privacy: .public)'")
        }
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
    /// Also renames the co-located asset directory and rewrites image paths in the body.
    /// Returns the new filename and, if image paths were rewritten, the updated content.
    @discardableResult
    static func writeNote(_ note: Note) throws -> (filename: String, updatedContent: String?, savedAt: Date) {
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
            try Data(note.content.utf8).write(to: currentURL, options: .atomic)
            upsertSidecarEntry(for: note, filename: savedFilename)
            return (filename: savedFilename, updatedContent: nil, savedAt: modificationDate(for: note) ?? Date())
        }

        // Rename old file first if title changed (preserves macOS metadata)
        var updatedContent: String? = nil
        if let oldFilename = note.savedFilename, oldFilename != newFilename {
            let oldRelative = note.folder.isEmpty ? oldFilename : "\(note.folder)/\(oldFilename)"
            let oldURL = rootURL.appendingPathComponent(oldRelative)
            if FileManager.default.fileExists(atPath: oldURL.path) {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                Log.storage.debug("[FileStorage] renamed \(oldFilename, privacy: .public) → \(newFilename, privacy: .public)")
            }

            // Rename asset dir and rewrite image paths in body
            let oldStem = (oldFilename as NSString).deletingPathExtension
            let newStem = (newFilename as NSString).deletingPathExtension
            if oldStem != newStem {
                let oldAsset = assetDirURL(stem: oldStem, folder: note.folder)
                let newAsset = assetDirURL(stem: newStem, folder: note.folder)
                if FileManager.default.fileExists(atPath: oldAsset.path) {
                    if FileManager.default.fileExists(atPath: newAsset.path) {
                        // Merge — UUID filenames guarantee no collision
                        let existing = (try? FileManager.default.contentsOfDirectory(
                            at: oldAsset, includingPropertiesForKeys: nil,
                        )) ?? []
                        for f in existing {
                            try? FileManager.default.moveItem(
                                at: f, to: newAsset.appendingPathComponent(f.lastPathComponent),
                            )
                        }
                        try? FileManager.default.removeItem(at: oldAsset)
                    } else {
                        try? FileManager.default.moveItem(at: oldAsset, to: newAsset)
                    }
                    Log.storage.info("[Image] renamed asset dir .\(oldStem, privacy: .public) → .\(newStem, privacy: .public)")
                    // Rewrite image refs in body — scoped to actual filenames, no false positives
                    var body = note.content
                    let imgs = (try? FileManager.default.contentsOfDirectory(
                        at: newAsset, includingPropertiesForKeys: nil,
                    )) ?? []
                    for f in imgs {
                        let name = f.lastPathComponent
                        body = body.replacingOccurrences(
                            of: "(." + oldStem + "/" + name + ")",
                            with: "(." + newStem + "/" + name + ")",
                        )
                    }
                    updatedContent = body
                }
            }
        }

        // Write body only — no YAML header
        let bodyToWrite = updatedContent ?? note.content
        try Data(bodyToWrite.utf8).write(to: newURL, options: .atomic)

        // Sync sidecar — use actual disk mtime as savedAt so the external-change
        // detector sees no diff on the next poll cycle.
        var noteForSidecar = note
        if updatedContent != nil {
            noteForSidecar.content = bodyToWrite
        }
        upsertSidecarEntry(for: noteForSidecar, filename: newFilename)

        let savedAt = modificationDate(for: noteForSidecar) ?? Date()
        return (filename: newFilename, updatedContent: updatedContent, savedAt: savedAt)
    }

    /// Update (or insert) the sidecar entry for a note after writing its file.
    private static func upsertSidecarEntry(for note: Note, filename: String) {
        let relativePath = note.folder.isEmpty ? filename : "\(note.folder)/\(filename)"
        let savedAt = (try? FileManager.default.attributesOfItem(
            atPath: rootURL.appendingPathComponent(relativePath).path,
        ))?[.modificationDate] as? Date ?? Date()

        SidecarStore.shared.upsertNote(
            SidecarStore.NoteEntry(
                path: relativePath,
                createdAt: note.createdAt,
                modifiedAt: note.modifiedAt,
                savedAt: savedAt,
                tags: note.tags.map(\.rawValue),
            ),
            for: note.id,
        )
        try? SidecarStore.shared.save()
    }

    static func deleteNote(_ note: Note) throws {
        let actualFilename = note.savedFilename ?? note.filename
        let relativePath = note.folder.isEmpty ? actualFilename : "\(note.folder)/\(actualFilename)"
        try FileManager.default.removeItem(at: rootURL.appendingPathComponent(relativePath))
        SidecarStore.shared.removeNote(id: note.id)
        try? SidecarStore.shared.save()
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

    /// Move a note to `toFolder`, optionally renaming the on-disk file to `newFilename`.
    /// When `newFilename` is nil, the existing on-disk filename is preserved — caller's
    /// `savedFilename ?? filename`. Pass an explicit name to atomically move + rename
    /// (used by the conflict-resolver's "Keep Both" path).
    @discardableResult
    static func moveNote(_ note: Note, toFolder: String, withFilename newFilename: String? = nil) throws -> Date {
        let actualFilename = note.savedFilename ?? note.filename
        let oldRelative = note.folder.isEmpty ? actualFilename : "\(note.folder)/\(actualFilename)"
        let oldURL = rootURL.appendingPathComponent(oldRelative)

        if !toFolder.isEmpty {
            try ensureFolderExists(toFolder)
        }
        let destFilename = newFilename ?? actualFilename
        let newRelative = toFolder.isEmpty ? destFilename : "\(toFolder)/\(destFilename)"
        let newURL = rootURL.appendingPathComponent(newRelative)
        try FileManager.default.moveItem(at: oldURL, to: newURL)

        // Move asset dir alongside note — rename stem too if filename changed.
        let oldStem = (actualFilename as NSString).deletingPathExtension
        let newStem = (destFilename as NSString).deletingPathExtension
        let srcAsset = assetDirURL(stem: oldStem, folder: note.folder)
        let dstAsset = assetDirURL(stem: newStem, folder: toFolder)
        if FileManager.default.fileExists(atPath: srcAsset.path) {
            try? FileManager.default.moveItem(at: srcAsset, to: dstAsset)
            Log.storage.debug("[Image] moved asset dir for '\(note.title, privacy: .public)' to folder '\(toFolder, privacy: .public)'")
        }

        // Update path and savedAt in sidecar — moveItem advances mtime
        let movedMtime = (try? FileManager.default.attributesOfItem(atPath: newURL.path))?[.modificationDate] as? Date ?? Date()
        if var entry = SidecarStore.shared.noteEntry(for: note.id) {
            entry.path = newRelative
            entry.savedAt = movedMtime
            SidecarStore.shared.upsertNote(entry, for: note.id)
            try? SidecarStore.shared.save()
        }
        return movedMtime
    }

    // MARK: - Trash I/O (Individual Notes)

    /// Move a note from its current location to `.trash/<UUID>_<Title>.md`.
    /// Updates YAML to include `folder:` (return address) and `trashed:`.
    /// Also moves the co-located asset directory to `.trash/.<UUID>_<Title>/`.
    static func trashNote(_ note: Note) throws {
        try ensureTrashExists()
        let trashFilename = "\(note.id.uuidString)_\(sanitizeForFilename(note.title)).md"
        let destURL = trashURL.appendingPathComponent(trashFilename)

        // Write body only to .trash/
        try Data(note.content.utf8).write(to: destURL, options: .atomic)

        // Remove original file
        let actualFilename = note.savedFilename ?? note.filename
        let oldRelative = note.folder.isEmpty ? actualFilename : "\(note.folder)/\(actualFilename)"
        try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(oldRelative))

        // Move sidecar entry from notes → trash
        SidecarStore.shared.removeNote(id: note.id)
        let originalPath = note.folder.isEmpty ? actualFilename : "\(note.folder)/\(actualFilename)"
        SidecarStore.shared.upsertTrash(
            SidecarStore.TrashEntry(
                filename: trashFilename,
                originalPath: originalPath,
                trashedAt: note.trashedAt ?? Date(),
                createdAt: note.createdAt,
                modifiedAt: note.modifiedAt,
                tags: note.tags.map(\.rawValue),
            ),
            for: note.id,
        )
        try? SidecarStore.shared.save()

        // Move asset dir to trash: .My-Note/ → .trash/.<UUID>_My-Note/
        let stem = sanitizeForFilename(note.title)
        let trashStem = (trashFilename as NSString).deletingPathExtension
        let srcAsset = assetDirURL(stem: stem, folder: note.folder)
        let dstAsset = assetDirURL(stem: trashStem, folder: "", inTrash: true)
        if FileManager.default.fileExists(atPath: srcAsset.path) {
            try? FileManager.default.moveItem(at: srcAsset, to: dstAsset)
            Log.storage.debug("[Image] moved asset dir to trash for '\(note.title, privacy: .public)'")
        }
    }

    /// Restore a note from `.trash/` back to its original folder.
    /// Returns the new `savedFilename`.
    static func restoreNote(_ note: Note) throws -> (filename: String, savedAt: Date) {
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

        // Write body only
        try Data(restored.content.utf8).write(to: destURL, options: .atomic)

        // Move sidecar entry from trash → notes
        SidecarStore.shared.removeTrash(id: note.id)
        let savedAt = (try? FileManager.default.attributesOfItem(atPath: destURL.path))?[.modificationDate] as? Date ?? Date()
        SidecarStore.shared.upsertNote(
            SidecarStore.NoteEntry(
                path: destRelative,
                createdAt: note.createdAt,
                modifiedAt: note.modifiedAt,
                savedAt: savedAt,
                tags: note.tags.map(\.rawValue),
            ),
            for: note.id,
        )
        try? SidecarStore.shared.save()

        let restoredSavedAt = savedAt

        // Remove from .trash/
        if let savedFilename = note.savedFilename {
            try? FileManager.default.removeItem(at: trashURL.appendingPathComponent(savedFilename))

            // Restore asset dir: .trash/.<UUID>_Title/ → <folder>/.Title/
            let trashStem = (savedFilename as NSString).deletingPathExtension
            let restoredStem = sanitizeForFilename(note.title)
            let srcAsset = assetDirURL(stem: trashStem, folder: "", inTrash: true)
            let dstAsset = assetDirURL(stem: restoredStem, folder: note.folder)
            if FileManager.default.fileExists(atPath: srcAsset.path) {
                try? FileManager.default.moveItem(at: srcAsset, to: dstAsset)
                Log.storage.debug("[Image] restored asset dir for '\(note.title, privacy: .public)'")
            }
        }

        return (filename: newFilename, savedAt: restoredSavedAt)
    }

    /// Delete a trashed note from `.trash/`. Also deletes its asset directory.
    static func deleteTrashedNote(_ note: Note) throws {
        if let savedFilename = note.savedFilename {
            try FileManager.default.removeItem(at: trashURL.appendingPathComponent(savedFilename))

            // Delete asset dir: .trash/.<UUID>_Title/
            let trashStem = (savedFilename as NSString).deletingPathExtension
            let assetDir = assetDirURL(stem: trashStem, folder: "", inTrash: true)
            if FileManager.default.fileExists(atPath: assetDir.path) {
                try? FileManager.default.removeItem(at: assetDir)
                Log.storage.debug("[Image] deleted asset dir for permanently deleted note '\(note.title, privacy: .public)'")
            }
        }
        SidecarStore.shared.removeTrash(id: note.id)
        try? SidecarStore.shared.save()
    }

    /// Load individually trashed notes from `.trash/` (top-level `.md` files only).
    static func loadTrashedNotes() throws -> [Note] {
        try ensureTrashExists()
        let contents = try FileManager.default.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
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

        // Move sidecar note entries → trash entries for every note inside this folder.
        // The trash entry's `filename` is relative to .trash/ (e.g. "UUID_Projects/Note.md")
        // so `readNote` can find it by full relative path on the next launch.
        let folderPrefix = name + "/"
        let noteKeys = SidecarStore.shared.data.notes.compactMap { kv -> String? in
            kv.value.path.hasPrefix(folderPrefix) ? kv.key : nil
        }
        for key in noteKeys {
            if let entry = SidecarStore.shared.data.notes.removeValue(forKey: key),
               let noteID = UUID(uuidString: key)
            {
                let relativeWithinFolder = String(entry.path.dropFirst(folderPrefix.count))
                SidecarStore.shared.upsertTrash(SidecarStore.TrashEntry(
                    filename: "\(trashDirname)/\(relativeWithinFolder)",
                    originalPath: entry.path,
                    trashedAt: trashedAt,
                    createdAt: entry.createdAt,
                    modifiedAt: entry.modifiedAt,
                    tags: entry.tags,
                ), for: noteID)
            }
        }
        try? SidecarStore.shared.save()

        // Write .folder.md metadata
        let folderMeta = """
        ---
        trashedAt: \(dateFormatter.string(from: trashedAt))
        originalPath: \(name)
        ---
        """
        let metaURL = destURL.appendingPathComponent(".folder.md")
        try Data(folderMeta.utf8).write(to: metaURL, options: .atomic)
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

        // Move sidecar trash entries back to notes for every note in the restored folder
        let trashPrefix = folder.savedDirname + "/"
        let trashKeys = SidecarStore.shared.data.trash.compactMap { kv -> String? in
            kv.value.filename.hasPrefix(trashPrefix) ? kv.key : nil
        }
        for key in trashKeys {
            if let entry = SidecarStore.shared.data.trash.removeValue(forKey: key),
               let noteID = UUID(uuidString: key)
            {
                // Read actual mtime after moveItem so savedAt matches disk reality.
                // moveItem advances mtime to now; using entry.modifiedAt (the old value)
                // would make checkForExternalChanges see file mtime > savedAt immediately.
                let noteURL = rootURL.appendingPathComponent(entry.originalPath)
                let actualMtime = (try? FileManager.default.attributesOfItem(
                    atPath: noteURL.path,
                ))?[.modificationDate] as? Date ?? entry.modifiedAt

                SidecarStore.shared.upsertNote(SidecarStore.NoteEntry(
                    path: entry.originalPath,
                    createdAt: entry.createdAt,
                    modifiedAt: entry.modifiedAt,
                    savedAt: actualMtime,
                    tags: entry.tags,
                ), for: noteID)
            }
        }
        try? SidecarStore.shared.save()
    }

    /// Permanently delete a trashed folder from `.trash/`.
    static func deleteTrashedFolder(_ folder: TrashedFolder) throws {
        let url = trashURL.appendingPathComponent(folder.savedDirname, isDirectory: true)
        try FileManager.default.removeItem(at: url)

        // Remove sidecar trash entries for every note inside this folder
        let trashPrefix = folder.savedDirname + "/"
        let keysToRemove = SidecarStore.shared.data.trash.compactMap { kv -> String? in
            kv.value.filename.hasPrefix(trashPrefix) ? kv.key : nil
        }
        for key in keysToRemove {
            SidecarStore.shared.data.trash.removeValue(forKey: key)
        }
        if !keysToRemove.isEmpty {
            try? SidecarStore.shared.save()
        }
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
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let filename = url.lastPathComponent

        // Determine relative path for sidecar lookup.
        // Trash files live under trashURL, active notes under rootURL.
        let isTrash = url.path.hasPrefix(trashURL.path)
        // Full path relative to its storage root (.trash/ or rootURL) so sidecar
        // lookups work for both bare files ("UUID_Title.md") and folder-nested files
        // ("UUID_Projects/SubFolder/Note.md").
        let relativePath: String
        if isTrash {
            let prefix = trashURL.path
            relativePath = url.path.hasPrefix(prefix)
                ? String(url.path.dropFirst(prefix.count + 1))
                : filename
        } else {
            let prefix = rootURL.path
            relativePath = url.path.hasPrefix(prefix)
                ? String(url.path.dropFirst(prefix.count + 1))
                : filename
        }

        // --- Sidecar path (preferred) ---
        if isTrash {
            if let (id, entry) = SidecarStore.shared.trashEntry(forFilename: relativePath) {
                let (_, body) = parseFrontMatter(text) // strip any residual YAML
                let content = text.hasPrefix("---") ? body : text
                let tags = entry.tags.compactMap { TagColor(rawValue: $0) }
                let folder = (entry.originalPath as NSString).deletingLastPathComponent
                let resolvedFolder = folder == "." || folder.isEmpty ? "" : folder
                return Note(
                    id: id,
                    title: extractTitle(from: content),
                    content: content,
                    createdAt: entry.createdAt,
                    modifiedAt: entry.modifiedAt,
                    savedAt: entry.modifiedAt,
                    folder: resolvedFolder,
                    tags: tags,
                    trashedAt: entry.trashedAt,
                    savedFilename: filename,
                )
            }
        } else {
            if let (id, entry) = SidecarStore.shared.noteEntry(forPath: relativePath) {
                let (_, body) = parseFrontMatter(text)
                let content = text.hasPrefix("---") ? body : text
                let tags = entry.tags.compactMap { TagColor(rawValue: $0) }
                return Note(
                    id: id,
                    title: extractTitle(from: content),
                    content: content,
                    createdAt: entry.createdAt,
                    modifiedAt: entry.modifiedAt,
                    savedAt: entry.savedAt,
                    folder: folder,
                    tags: tags,
                    savedFilename: filename,
                )
            }
        }

        // --- YAML fallback (unmigrated file or sidecar entry missing) ---
        let (metadata, body) = parseFrontMatter(text)
        if !metadata.isEmpty {
            let id = metadata["id"].flatMap { UUID(uuidString: $0) } ?? UUID()
            let title = metadata["title"] ?? extractTitle(from: body)
            let created = metadata["created"].flatMap { dateFormatter.date(from: $0) } ?? Date()
            let modified = metadata["modified"].flatMap { dateFormatter.date(from: $0) } ?? Date()
            let trashed = metadata["trashed"].flatMap { dateFormatter.date(from: $0) }
            let tags = parseTagList(metadata["tags"] ?? "")
            let resolvedFolder = metadata["folder"] ?? folder

            // Inject into sidecar so future reads don't need to parse YAML
            if isTrash {
                let originalPath = resolvedFolder.isEmpty ? "\(title).md" : "\(resolvedFolder)/\(title).md"
                SidecarStore.shared.upsertTrash(SidecarStore.TrashEntry(
                    filename: relativePath,
                    originalPath: originalPath,
                    trashedAt: trashed ?? modified,
                    createdAt: created,
                    modifiedAt: modified,
                    tags: tags.map(\.rawValue),
                ), for: id)
            } else {
                SidecarStore.shared.upsertNote(SidecarStore.NoteEntry(
                    path: relativePath,
                    createdAt: created,
                    modifiedAt: modified,
                    savedAt: modified,
                    tags: tags.map(\.rawValue),
                ), for: id)
            }
            try? SidecarStore.shared.save()

            return Note(
                id: id,
                title: title,
                content: body,
                createdAt: created,
                modifiedAt: modified,
                savedAt: modified,
                folder: resolvedFolder,
                tags: tags,
                trashedAt: trashed,
                savedFilename: filename,
            )
        }

        // --- External file: no sidecar entry, no YAML ---
        let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let created = resourceValues?.creationDate ?? Date()
        let modified = resourceValues?.contentModificationDate ?? Date()
        let id = UUID()

        if isTrash {
            SidecarStore.shared.upsertTrash(SidecarStore.TrashEntry(
                filename: relativePath,
                originalPath: "\(folder.isEmpty ? "" : folder + "/")\(filename)",
                trashedAt: modified,
                createdAt: created,
                modifiedAt: modified,
                tags: [],
            ), for: id)
        } else {
            SidecarStore.shared.upsertNote(SidecarStore.NoteEntry(
                path: relativePath,
                createdAt: created,
                modifiedAt: modified,
                savedAt: modified,
                tags: [],
            ), for: id)
        }
        try? SidecarStore.shared.save()

        return Note(
            id: id,
            title: extractTitle(from: text),
            content: text,
            createdAt: created,
            modifiedAt: modified,
            savedAt: modified,
            folder: folder,
            savedFilename: filename,
        )
    }

    /// Parses `[red, blue]` (with or without surrounding brackets / quotes / spaces)
    /// into a list of valid TagColors. Unknown names are silently dropped.
    private static func parseTagList(_ raw: String) -> [TagColor] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let stripped = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return stripped.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
            .compactMap { TagColor(rawValue: $0.lowercased()) }
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
        if !note.tags.isEmpty {
            let names = note.tags.map(\.rawValue).joined(separator: ", ")
            lines.append("tags: [\(names)]")
        }
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
                try Data(note.content.utf8).write(to: newURL, options: .atomic)
                if oldURL != newURL {
                    try? FileManager.default.removeItem(at: oldURL)
                }
                note.savedFilename = note.filename
                // Update sidecar path for the renamed note
                if var entry = SidecarStore.shared.noteEntry(for: note.id) {
                    entry.path = note.relativePath
                    SidecarStore.shared.upsertNote(entry, for: note.id)
                }
                result[duplicateIndex] = note
            }
        }
        try? SidecarStore.shared.save()
        return result
    }

    private static func extractTitle(from content: String) -> String {
        let firstLine = content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        // Strip leading # for markdown headings
        let stripped = firstLine.drop { $0 == "#" || $0 == " " }
        return stripped.isEmpty ? "Untitled" : String(stripped)
    }
}
