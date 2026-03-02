import Foundation
import OSLog
import SwiftUI

@Observable
final class NoteStore {
    // MARK: - State

    var notes: [Note] = []
    var trashedNotes: [Note] = []
    var trashedFolders: [TrashedFolder] = []
    var folders: [Folder] = []
    var selectedFolder: Folder?
    var selectedNote: Note?
    var showTrash = false

    // MARK: - Navigation Direction

    enum NavigationDirection {
        case forward
        case backward
        case overlay
        case none
    }

    var navigationDirection: NavigationDirection = .none

    /// Pending note move that has a name conflict — UI shows confirmation dialog.
    struct PendingNoteMoveConflict {
        let noteID: UUID
        let targetFolder: String
    }

    var pendingNoteMoveConflict: PendingNoteMoveConflict?

    /// Pending folder move that has a name conflict — UI shows confirmation dialog.
    struct PendingFolderMoveConflict {
        let folderName: String
        let targetParent: String
    }

    var pendingFolderMoveConflict: PendingFolderMoveConflict?

    /// Notes filtered by selected folder (unsorted — views apply sort via `sortedNotes`).
    var filteredNotes: [Note] {
        if let folder = selectedFolder {
            notes.filter { $0.folder == folder.name }
        } else {
            notes
        }
    }

    // MARK: - Sorting

    func sortedNotes(_ notes: [Note], by sortBy: AppSettings.SortBy, ascending: Bool) -> [Note] {
        notes.sorted { a, b in
            let result: Bool = switch sortBy {
            case .name:
                a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case .dateModified:
                a.modifiedAt < b.modifiedAt
            case .dateCreated:
                a.createdAt < b.createdAt
            }
            return ascending ? result : !result
        }
    }

    func sortedFolders(_ folders: [Folder], by sortBy: AppSettings.SortBy, ascending: Bool) -> [Folder] {
        folders.sorted { a, b in
            let result: Bool = switch sortBy {
            case .name:
                a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .dateModified:
                // nil dates (empty folders) sort to end
                switch (a.latestModifiedAt, b.latestModifiedAt) {
                case let (aDate?, bDate?): aDate < bDate
                case (nil, _): false
                case (_, nil): true
                }
            case .dateCreated:
                switch (a.earliestCreatedAt, b.earliestCreatedAt) {
                case let (aDate?, bDate?): aDate < bDate
                case (nil, _): false
                case (_, nil): true
                }
            }
            return ascending ? result : !result
        }
    }

    // MARK: - Animated Navigation

    func navigateToFolder(_ folder: Folder) {
        let name = folder.name
        Log.navigation.debug("[NoteStore] navigateToFolder — \(name, privacy: .public)")
        navigationDirection = .forward
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedFolder = folder
        }
    }

    func navigateToSubfolder(_ folder: Folder) {
        let name = folder.name
        Log.navigation.debug("[NoteStore] navigateToSubfolder — \(name, privacy: .public)")
        navigationDirection = .forward
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedFolder = folder
        }
    }

    func navigateBack() {
        let from = selectedNote?.title ?? selectedFolder?.name ?? "home"
        Log.navigation.debug("[NoteStore] navigateBack from \(from, privacy: .public)")
        navigationDirection = .backward
        if selectedNote != nil {
            saveDirtyNotes()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedNote = nil
            }
        } else if let parent = selectedFolder?.parentPath, !parent.isEmpty {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFolder = folders.first { $0.name == parent }
                    ?? Folder(name: parent, noteCount: 0)
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFolder = nil
            }
        }
    }

    func openNote(_ note: Note) {
        let title = note.title
        Log.navigation.debug("[NoteStore] openNote — \(title, privacy: .public)")
        navigationDirection = .forward
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedNote = note
        }
    }

    func openNoteFromSearch(_ note: Note) {
        let title = note.title
        let folder = note.folder
        Log.navigation.debug("[NoteStore] openNoteFromSearch — \(title, privacy: .public) in \(folder, privacy: .public)")
        if !note.folder.isEmpty {
            selectedFolder = Folder(name: note.folder, noteCount: 0)
        }
        navigationDirection = .forward
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedNote = note
        }
    }

    func closeNote() {
        let title = selectedNote?.title ?? "nil"
        Log.navigation.debug("[NoteStore] closeNote — \(title, privacy: .public)")
        navigationDirection = .backward
        saveDirtyNotes()
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedNote = nil
        }
    }

    @discardableResult
    func createAndOpenNote(in folder: String = "") -> Note {
        let note = createNote(in: folder)
        let title = note.title
        Log.navigation.info("[NoteStore] createAndOpenNote — \(title, privacy: .public) in \(folder, privacy: .public)")
        navigationDirection = .forward
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedNote = note
        }
        return note
    }

    func openTrash() {
        Log.navigation.debug("[NoteStore] openTrash")
        navigationDirection = .overlay
        withAnimation(.easeInOut(duration: 0.2)) {
            showTrash = true
        }
    }

    func closeTrash() {
        Log.navigation.debug("[NoteStore] closeTrash")
        navigationDirection = .overlay
        withAnimation(.easeInOut(duration: 0.2)) {
            showTrash = false
        }
    }

    // MARK: - Dirty Tracking

    private var dirtyNoteIDs: Set<UUID> = []

    // MARK: - Lifecycle

    func loadFromDisk() {
        do {
            notes = try FileStorage.loadAllNotes()
            trashedNotes = try FileStorage.loadTrashedNotes()
            trashedFolders = try FileStorage.loadTrashedFolders()
            autoPurgeExpiredTrash()
            refreshFolders()
            let noteCount = notes.count
            let trashCount = trashedNotes.count + trashedFolders.count
            Log.storage.info("[NoteStore] loaded \(noteCount) notes, \(trashCount) trashed items")
        } catch {
            Log.storage.error("[NoteStore] loadFromDisk failed — \(error)")
        }
    }

    // MARK: - Duplicate Detection

    /// Whether a note title already exists in the given folder (case-insensitive filename match).
    func noteTitleExists(_ title: String, in folder: String, excluding noteID: UUID? = nil) -> Bool {
        let sanitized = FileStorage.sanitizeForFilename(title)
        return notes.contains { note in
            note.id != noteID
                && note.folder == folder
                && FileStorage.sanitizeForFilename(note.title).caseInsensitiveCompare(sanitized) == .orderedSame
        }
    }

    // MARK: - Note CRUD

    func createNote(in folder: String = "") -> Note {
        var title = "Untitled"
        var counter = 2
        while noteTitleExists(title, in: folder) {
            title = "Untitled \(counter)"
            counter += 1
        }
        let now = Date()
        var note = Note(
            id: UUID(),
            title: title,
            content: "# \(title)\n\n",
            createdAt: now,
            modifiedAt: now,
            folder: folder,
        )
        do {
            let savedName = try FileStorage.writeNote(note)
            note.savedFilename = savedName
        } catch {
            Log.storage.error("[NoteStore] writeNote failed — \(error)")
        }
        notes.append(note)
        refreshFolders()
        return note
    }

    func updateContent(for noteID: UUID, content: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[index].content = content
        notes[index].modifiedAt = Date()
        notes[index].title = Self.extractTitle(from: content)
        dirtyNoteIDs.insert(noteID)

        // Also update selectedNote if it matches
        if selectedNote?.id == noteID {
            selectedNote = notes[index]
        }
    }

    func renameNote(_ note: Note, to newTitle: String) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !noteTitleExists(trimmed, in: note.folder, excluding: note.id) else { return }

        notes[index].title = trimmed
        notes[index].modifiedAt = Date()

        // Update the first # heading line in content to match the new title
        var lines = notes[index].content.components(separatedBy: "\n")
        if let headingIndex = lines.firstIndex(where: { $0.hasPrefix("#") }) {
            let prefix = String(lines[headingIndex].prefix(while: { $0 == "#" }))
            lines[headingIndex] = "\(prefix) \(trimmed)"
            notes[index].content = lines.joined(separator: "\n")
        }

        dirtyNoteIDs.insert(note.id)

        if selectedNote?.id == note.id {
            selectedNote = notes[index]
        }
    }

    func deleteNote(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        dirtyNoteIDs.remove(note.id)
        do {
            try FileStorage.deleteNote(note)
        } catch {
            Log.storage.error("[NoteStore] deleteNote failed — \(error)")
        }
        refreshFolders()
    }

    func moveNote(_ note: Note, to folder: String) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        if noteTitleExists(notes[index].title, in: folder, excluding: note.id) {
            pendingNoteMoveConflict = PendingNoteMoveConflict(noteID: note.id, targetFolder: folder)
            return
        }
        performMoveNote(at: index, to: folder)
    }

    func resolveNoteMoveConflict(keepBoth: Bool) {
        guard let conflict = pendingNoteMoveConflict,
              let index = notes.firstIndex(where: { $0.id == conflict.noteID })
        else {
            pendingNoteMoveConflict = nil
            return
        }
        let title = notes[index].title
        let folder = conflict.targetFolder

        if keepBoth {
            var counter = 2
            var newTitle = "\(title) \(counter)"
            while noteTitleExists(newTitle, in: folder, excluding: conflict.noteID) {
                counter += 1
                newTitle = "\(title) \(counter)"
            }
            notes[index].title = newTitle
            notes[index].modifiedAt = Date()
            var lines = notes[index].content.components(separatedBy: "\n")
            if let headingIdx = lines.firstIndex(where: { $0.hasPrefix("#") }) {
                let prefix = String(lines[headingIdx].prefix(while: { $0 == "#" }))
                lines[headingIdx] = "\(prefix) \(newTitle)"
                notes[index].content = lines.joined(separator: "\n")
            }
        } else {
            if let existing = notes.first(where: {
                $0.id != conflict.noteID
                    && $0.folder == folder
                    && FileStorage.sanitizeForFilename($0.title)
                    .caseInsensitiveCompare(FileStorage.sanitizeForFilename(title)) == .orderedSame
            }) {
                trashNote(existing)
            }
        }

        if let idx = notes.firstIndex(where: { $0.id == conflict.noteID }) {
            performMoveNote(at: idx, to: folder)
        }
        pendingNoteMoveConflict = nil
    }

    private func performMoveNote(at index: Int, to folder: String) {
        let note = notes[index]
        do {
            try FileStorage.moveNote(note, toFolder: folder)
            notes[index].folder = folder
            notes[index].savedFilename = notes[index].filename
            refreshFolders()
        } catch {
            Log.storage.error("[NoteStore] moveNote failed — \(error)")
        }
    }

    // MARK: - Trash

    func trashNote(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].trashedAt = Date()
        dirtyNoteIDs.remove(note.id)

        // Move file to .trash/<UUID>_<Title>.md
        do {
            try FileStorage.trashNote(notes[index])
            let trashFilename = "\(notes[index].id.uuidString)_\(FileStorage.sanitizeForFilename(notes[index].title)).md"
            notes[index].savedFilename = trashFilename
        } catch {
            Log.storage.error("[NoteStore] trashNote failed — \(error)")
        }

        let trashedNote = notes.remove(at: index)
        trashedNotes.append(trashedNote)

        if selectedNote?.id == note.id {
            navigationDirection = .backward
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedNote = nil
            }
        }
        refreshFolders()
    }

    func trashFolder(_ name: String) {
        guard !name.isEmpty else { return }
        let prefix = name + "/"
        let now = Date()
        let folderID = UUID()

        // Collect notes in this folder and subfolders
        let folderNotes = notes.filter { $0.folder == name || $0.folder.hasPrefix(prefix) }

        // Move entire folder directory to .trash/
        do {
            try FileStorage.trashFolder(name, id: folderID, trashedAt: now)
        } catch {
            Log.storage.error("[NoteStore] trashFolder failed — \(error)")
            return
        }

        // Remove notes from active array
        notes.removeAll { $0.folder == name || $0.folder.hasPrefix(prefix) }

        let displayName = (name as NSString).lastPathComponent
        let savedDirname = "\(folderID.uuidString)_\(displayName)"
        trashedFolders.append(TrashedFolder(
            id: folderID,
            displayName: displayName,
            originalPath: name,
            trashedAt: now,
            notes: folderNotes,
            savedDirname: savedDirname,
        ))

        // Navigate away if inside this folder or any descendant
        if selectedFolder?.name == name || (selectedFolder?.name.hasPrefix(prefix) ?? false) {
            navigationDirection = .backward
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFolder = nil
            }
        }

        // Deselect note if it was in the trashed folder
        if let sel = selectedNote, sel.folder == name || sel.folder.hasPrefix(prefix) {
            navigationDirection = .backward
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedNote = nil
            }
        }

        refreshFolders()
    }

    func restoreNote(_ note: Note) {
        guard let index = trashedNotes.firstIndex(where: { $0.id == note.id }) else { return }
        trashedNotes[index].trashedAt = nil

        // Move file from .trash/ back to original folder
        do {
            let newFilename = try FileStorage.restoreNote(trashedNotes[index])
            trashedNotes[index].savedFilename = newFilename
        } catch {
            Log.storage.error("[NoteStore] restoreNote failed — \(error)")
        }

        let restoredNote = trashedNotes.remove(at: index)
        notes.append(restoredNote)
        refreshFolders()
    }

    func restoreFolder(_ folder: TrashedFolder) {
        do {
            try FileStorage.restoreFolder(folder)
        } catch {
            Log.storage.error("[NoteStore] restoreFolder failed — \(error)")
            return
        }

        // Reload notes from the restored folder
        let restoredNotes = folder.notes
        notes.append(contentsOf: restoredNotes)
        trashedFolders.removeAll { $0.id == folder.id }
        refreshFolders()
    }

    func permanentlyDeleteNote(_ note: Note) {
        trashedNotes.removeAll { $0.id == note.id }
        do {
            try FileStorage.deleteTrashedNote(note)
        } catch {
            Log.storage.error("[NoteStore] permanentlyDeleteNote failed — \(error)")
        }
    }

    func permanentlyDeleteFolder(_ folder: TrashedFolder) {
        trashedFolders.removeAll { $0.id == folder.id }
        do {
            try FileStorage.deleteTrashedFolder(folder)
        } catch {
            Log.storage.error("[NoteStore] permanentlyDeleteFolder failed — \(error)")
        }
    }

    func emptyTrash() {
        for note in trashedNotes {
            do {
                try FileStorage.deleteTrashedNote(note)
            } catch {
                Log.storage.error("[NoteStore] emptyTrash note failed — \(error)")
            }
        }
        trashedNotes.removeAll()

        for folder in trashedFolders {
            do {
                try FileStorage.deleteTrashedFolder(folder)
            } catch {
                Log.storage.error("[NoteStore] emptyTrash folder failed — \(error)")
            }
        }
        trashedFolders.removeAll()
    }

    /// Total number of items in trash (notes + folders).
    var trashItemCount: Int {
        trashedNotes.count + trashedFolders.count
    }

    /// Whether trash is empty (no notes and no folders).
    var isTrashEmpty: Bool {
        trashedNotes.isEmpty && trashedFolders.isEmpty
    }

    /// Permanently delete notes/folders that have been in trash for more than 60 days.
    private func autoPurgeExpiredTrash() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let expiredNotes = trashedNotes.filter { ($0.trashedAt ?? Date()) < cutoff }
        for note in expiredNotes {
            permanentlyDeleteNote(note)
        }
        let expiredFolders = trashedFolders.filter { $0.trashedAt < cutoff }
        for folder in expiredFolders {
            permanentlyDeleteFolder(folder)
        }
        let purgedCount = expiredNotes.count + expiredFolders.count
        if purgedCount > 0 {
            Log.storage.info("[NoteStore] auto-purged \(purgedCount) expired trash items")
        }
    }

    // MARK: - Folder CRUD

    func createFolder(named name: String, in parent: String = "") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let fullPath = parent.isEmpty ? trimmed : "\(parent)/\(trimmed)"
        do {
            try FileStorage.ensureFolderExists(fullPath)
            refreshFolders()
        } catch {
            Log.storage.error("[NoteStore] createFolder failed — \(error)")
        }
    }

    func renameFolder(_ oldName: String, to newName: String) {
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldName.isEmpty, !trimmedNew.isEmpty, oldName != trimmedNew else { return }
        // Build new full path: replace last component only
        let parent = (oldName as NSString).deletingLastPathComponent
        let parentPath = parent == "." ? "" : parent
        let newFullPath = parentPath.isEmpty ? trimmedNew : "\(parentPath)/\(trimmedNew)"
        guard !folders.contains(where: { $0.name == newFullPath }) else { return }

        do {
            try FileStorage.renameFolder(oldName, to: newFullPath)
            // Update notes in this folder AND all subfolders
            let oldPrefix = oldName + "/"
            for i in notes.indices {
                if notes[i].folder == oldName {
                    notes[i].folder = newFullPath
                } else if notes[i].folder.hasPrefix(oldPrefix) {
                    notes[i].folder = newFullPath + String(notes[i].folder.dropFirst(oldName.count))
                }
            }
            if selectedFolder?.name == oldName {
                selectedFolder = Folder(name: newFullPath, noteCount: selectedFolder?.noteCount ?? 0)
            }
            refreshFolders()
        } catch {
            Log.storage.error("[NoteStore] renameFolder failed — \(error)")
        }
    }

    func moveFolder(_ name: String, toParent newParent: String) {
        guard !name.isEmpty else { return }
        let displayName = (name as NSString).lastPathComponent
        let newFullPath = newParent.isEmpty ? displayName : "\(newParent)/\(displayName)"
        guard newFullPath != name else { return }
        guard !newParent.hasPrefix(name + "/"), newParent != name else { return }

        // Check if a folder with the same name exists at the destination
        let siblings = newParent.isEmpty
            ? folders.filter(\.isTopLevel)
            : childFolders(of: newParent)
        let conflicts = siblings.contains {
            $0.name != name && $0.displayName.caseInsensitiveCompare(displayName) == .orderedSame
        }
        if conflicts {
            pendingFolderMoveConflict = PendingFolderMoveConflict(folderName: name, targetParent: newParent)
            return
        }
        performMoveFolder(name, toParent: newParent)
    }

    func resolveFolderMoveConflict(keepBoth: Bool) {
        guard let conflict = pendingFolderMoveConflict else {
            pendingFolderMoveConflict = nil
            return
        }
        let name = conflict.folderName
        let newParent = conflict.targetParent
        let displayName = (name as NSString).lastPathComponent
        let targetFullPath = newParent.isEmpty ? displayName : "\(newParent)/\(displayName)"

        if keepBoth {
            // Rename this folder with a number suffix before moving
            var counter = 2
            var newDisplayName = "\(displayName) \(counter)"
            let siblings = newParent.isEmpty
                ? folders.filter(\.isTopLevel)
                : childFolders(of: newParent)
            while siblings.contains(where: {
                $0.displayName.caseInsensitiveCompare(newDisplayName) == .orderedSame
            }) {
                counter += 1
                newDisplayName = "\(displayName) \(counter)"
            }
            // Rename locally first, then move
            renameFolder(name, to: newDisplayName)
            let renamedPath = (name as NSString).deletingLastPathComponent
            let renamedParent = renamedPath == "." ? "" : renamedPath
            let renamedFullPath = renamedParent.isEmpty ? newDisplayName : "\(renamedParent)/\(newDisplayName)"
            performMoveFolder(renamedFullPath, toParent: newParent)
        } else {
            // Replace: trash the existing folder at destination
            if let existingFolder = folders.first(where: {
                $0.name == targetFullPath
            }) {
                trashFolder(existingFolder.name)
            }
            performMoveFolder(name, toParent: newParent)
        }
        pendingFolderMoveConflict = nil
    }

    private func performMoveFolder(_ name: String, toParent newParent: String) {
        let displayName = (name as NSString).lastPathComponent
        let newFullPath = newParent.isEmpty ? displayName : "\(newParent)/\(displayName)"

        do {
            try FileStorage.moveFolder(name, toParent: newParent)
            let oldPrefix = name + "/"
            for i in notes.indices {
                if notes[i].folder == name {
                    notes[i].folder = newFullPath
                } else if notes[i].folder.hasPrefix(oldPrefix) {
                    notes[i].folder = newFullPath + "/" + String(notes[i].folder.dropFirst(oldPrefix.count))
                }
            }
            if selectedFolder?.name == name {
                selectedFolder = Folder(name: newFullPath, noteCount: selectedFolder?.noteCount ?? 0)
            }
            refreshFolders()
        } catch {
            Log.storage.error("[NoteStore] moveFolder failed — \(error)")
        }
    }

    /// Folders that are direct children of the given parent path.
    func childFolders(of parent: String) -> [Folder] {
        folders.filter { $0.parentPath == parent }
    }

    // MARK: - Save

    func saveDirtyNotes() {
        if !dirtyNoteIDs.isEmpty {
            let count = dirtyNoteIDs.count
            Log.storage.debug("[NoteStore] saving \(count) dirty notes")
        }
        for noteID in dirtyNoteIDs {
            guard let index = notes.firstIndex(where: { $0.id == noteID }) else { continue }
            do {
                let newFilename = try FileStorage.writeNote(notes[index])
                notes[index].savedFilename = newFilename
                if selectedNote?.id == noteID {
                    selectedNote?.savedFilename = newFilename
                }
            } catch {
                Log.storage.error("[NoteStore] saveDirtyNotes failed for \(noteID) — \(error)")
            }
        }
        dirtyNoteIDs.removeAll()
    }

    // MARK: - Private

    private func refreshFolders() {
        let folderNames = Set(notes.map(\.folder)).filter { !$0.isEmpty }
        let diskFolders = (try? FileStorage.discoverFolders()) ?? []
        let allNames = folderNames.union(Set(diskFolders)).sorted()

        folders = allNames.map { name in
            let prefix = name + "/"
            // Count notes in this folder AND all subfolders (recursive)
            let descendantNotes = notes.filter { $0.folder == name || $0.folder.hasPrefix(prefix) }
            return Folder(
                name: name,
                noteCount: descendantNotes.count,
                latestModifiedAt: descendantNotes.map(\.modifiedAt).max(),
                earliestCreatedAt: descendantNotes.map(\.createdAt).min(),
            )
        }
    }

    private static func extractTitle(from content: String) -> String {
        let firstLine = content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let stripped = firstLine.drop { $0 == "#" || $0 == " " }
        return stripped.isEmpty ? "Untitled" : String(stripped)
    }
}
