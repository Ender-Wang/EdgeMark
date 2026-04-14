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

    /// Conflict when both EdgeMark and an external editor modified the same open note.
    struct PendingExternalChange {
        let noteID: UUID
        let diskContent: String
    }

    var pendingExternalChange: PendingExternalChange?

    /// Called when an open note is auto-synced from disk — pushes new content directly to the editor.
    var onNeedEditorReload: ((String) -> Void)?

    /// Cached set of folder paths that exist on disk (including empty folders).
    /// Updated only by disk-mutating folder operations — avoids a full filesystem
    /// enumeration on every `refreshFolders()` call.
    private var diskFolderNames: Set<String> = []

    /// Set to true to trigger the search bar on HomeFolderView after navigating back.
    var pendingSearchOnHome = false

    /// Folder to return to when the user dismisses search (set when search is triggered from a subfolder).
    var searchReturnFolder: Folder?

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

    func navigateToHome() {
        Log.navigation.debug("[NoteStore] navigateToHome")
        navigationDirection = .backward
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedNote = nil
            selectedFolder = nil
        }
    }

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

    /// Notes in the current folder only (not descendants). Root = notes with empty folder.
    private var currentFolderNotes: [Note] {
        if let folder = selectedFolder {
            notes.filter { $0.folder == folder.name }
        } else {
            notes.filter(\.folder.isEmpty)
        }
    }

    func navigateToNextNote(sortedBy appSettings: AppSettings) {
        guard let current = selectedNote else { return }
        let sorted = sortedNotes(currentFolderNotes, by: appSettings.sortBy, ascending: appSettings.sortAscending)
        guard let index = sorted.firstIndex(where: { $0.id == current.id }),
              index + 1 < sorted.count
        else { return }
        let next = sorted[index + 1]
        let title = next.title
        Log.navigation.debug("[NoteStore] navigateToNextNote — \(title, privacy: .public)")
        saveDirtyNotes()
        navigationDirection = .forward
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedNote = next
        }
    }

    func navigateToPreviousNote(sortedBy appSettings: AppSettings) {
        guard let current = selectedNote else { return }
        let sorted = sortedNotes(currentFolderNotes, by: appSettings.sortBy, ascending: appSettings.sortAscending)
        guard let index = sorted.firstIndex(where: { $0.id == current.id }),
              index > 0
        else { return }
        let prev = sorted[index - 1]
        let title = prev.title
        Log.navigation.debug("[NoteStore] navigateToPreviousNote — \(title, privacy: .public)")
        saveDirtyNotes()
        navigationDirection = .backward
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedNote = prev
        }
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
            let loaded = try FileStorage.loadAllNotes()
            // Auto-correct duplicate UUIDs — reassign a new UUID to any duplicate and re-save
            // to disk so both notes survive (e.g. user copied a .md file in Finder)
            var seen = Set<UUID>()
            notes = loaded.map { note in
                guard seen.insert(note.id).inserted else {
                    let newID = UUID()
                    Log.storage.warning("[NoteStore] duplicate UUID '\(note.id)' for '\(note.title, privacy: .public)' — reassigning to \(newID)")
                    let fixed = Note(
                        id: newID,
                        title: note.title,
                        content: note.content,
                        createdAt: note.createdAt,
                        modifiedAt: note.modifiedAt,
                        folder: note.folder,
                        trashedAt: note.trashedAt,
                        savedFilename: note.savedFilename,
                    )
                    do {
                        try FileStorage.writeNote(fixed) // return value intentionally discarded (dedup path)
                    } catch {
                        Log.storage.error("[NoteStore] failed to re-save deduped note — \(error)")
                    }
                    return fixed
                }
                return note
            }
            trashedNotes = try FileStorage.loadTrashedNotes()
            trashedFolders = try FileStorage.loadTrashedFolders()
            autoPurgeExpiredTrash()
            diskFolderNames = Set((try? FileStorage.discoverFolders()) ?? [])
            refreshFolders()
            let noteCount = notes.count
            let trashCount = trashedNotes.count + trashedFolders.count
            Log.storage.info("[NoteStore] loaded \(noteCount) notes, \(trashCount) trashed items")
        } catch {
            Log.storage.error("[NoteStore] loadFromDisk failed — \(error)")
        }
    }

    /// Called on every app foreground transition. Checks each note for external modifications
    /// and reloads or prompts based on dirty state.
    func checkForExternalChanges() {
        let count = notes.count
        Log.storage.debug("[ExternalSync] checking \(count) notes")
        for i in notes.indices {
            let note = notes[i]
            guard let diskDate = FileStorage.modificationDate(for: note) else {
                let t = note.title
                Log.storage.debug("[ExternalSync] '\(t, privacy: .public)' — file not found on disk")
                continue
            }
            let inMemDate = note.modifiedAt
            let diff = diskDate.timeIntervalSince(inMemDate)
            let t = note.title
            Log.storage.debug("[ExternalSync] '\(t, privacy: .public)' — diff: \(String(format: "%.3f", diff))s")
            guard diff > 1 else { continue }

            let noteID = notes[i].id
            let isOpen = selectedNote?.id == noteID
            let isDirty = dirtyNoteIDs.contains(noteID)

            guard let (diskContent, diskModifiedAt) = FileStorage.reloadContent(for: notes[i]) else { continue }

            let title = notes[i].title
            if isOpen, isDirty {
                // Both EdgeMark and external have changes — prompt user
                Log.storage.info("[NoteStore] external conflict on open note '\(title, privacy: .public)'")
                pendingExternalChange = PendingExternalChange(noteID: noteID, diskContent: diskContent)
            } else {
                // Safe to auto-reload: note not open, or open but no EdgeMark edits
                Log.storage.info("[NoteStore] auto-syncing '\(title, privacy: .public)' from external change")
                notes[i].content = diskContent
                notes[i].modifiedAt = diskModifiedAt
                dirtyNoteIDs.remove(noteID)
                if isOpen {
                    selectedNote = notes[i]
                    // Push content directly to the editor — don't rely on SwiftUI update cycle
                    onNeedEditorReload?(diskContent)
                }
            }
        }
    }

    /// Resolve external conflict: keep EdgeMark edits (discard disk) or reload from disk.
    func resolveExternalChange(keepEdgeMarkEdits: Bool) {
        guard let conflict = pendingExternalChange else { return }
        pendingExternalChange = nil
        if !keepEdgeMarkEdits,
           let i = notes.firstIndex(where: { $0.id == conflict.noteID })
        {
            notes[i].content = conflict.diskContent
            dirtyNoteIDs.remove(conflict.noteID)
            if selectedNote?.id == conflict.noteID {
                selectedNote = notes[i]
                onNeedEditorReload?(conflict.diskContent)
            }
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
            let result = try FileStorage.writeNote(note)
            note.savedFilename = result.filename
        } catch {
            Log.storage.error("[NoteStore] writeNote failed — \(error)")
        }
        notes.append(note)
        refreshFolders()
        return note
    }

    func updateContent(for noteID: UUID, content: String) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        guard notes[index].content != content else { return }
        notes[index].content = content
        notes[index].modifiedAt = Date()
        // Only derive title from content when an explicit # heading is present.
        // Without this guard, a rename on a headingless note reverts within ~150ms
        // because the editor fires contentChanged on load and extractTitle returns
        // the raw first line, overwriting the manually-set title.
        let firstLine = content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        if firstLine.hasPrefix("#") {
            notes[index].title = Self.extractTitle(from: content)
        }
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

        // Remove trashed folder and all sub-paths from cache
        let oldPrefix = name + "/"
        diskFolderNames = diskFolderNames.filter { $0 != name && !$0.hasPrefix(oldPrefix) }
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
            diskFolderNames.insert(fullPath)
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
            // Update cache: rename oldName and all sub-paths (reuses oldPrefix declared above)
            diskFolderNames = Set(diskFolderNames.map { path in
                if path == oldName { return newFullPath }
                if path.hasPrefix(oldPrefix) { return newFullPath + path.dropFirst(oldName.count) }
                return path
            })
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
            // Update cache: rename moved folder and all sub-paths (reuses oldPrefix declared above)
            diskFolderNames = Set(diskFolderNames.map { path in
                if path == name { return newFullPath }
                if path.hasPrefix(oldPrefix) { return newFullPath + "/" + path.dropFirst(oldPrefix.count) }
                return path
            })
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
                let result = try FileStorage.writeNote(notes[index])
                notes[index].savedFilename = result.filename
                // If a rename rewrote image paths in the body, sync back to in-memory state
                // and reload the editor so the JS sees the updated relative paths immediately.
                if let updated = result.updatedContent {
                    notes[index].content = updated
                    if selectedNote?.id == noteID {
                        selectedNote?.content = updated
                        let noteTitle = notes[index].title
                        Log.storage.info("[Image] reloading editor after image path rewrite for '\(noteTitle, privacy: .public)'")
                        onNeedEditorReload?(updated)
                    }
                }
                // Sync modifiedAt to actual filesystem date so external change detection
                // doesn't false-positive (disk write happens a few ms after Date() is captured)
                if let diskDate = FileStorage.modificationDate(for: notes[index]) {
                    notes[index].modifiedAt = diskDate
                }
                if selectedNote?.id == noteID {
                    selectedNote?.savedFilename = result.filename
                    selectedNote?.modifiedAt = notes[index].modifiedAt
                }
                // Clean up orphaned images (deleted from body but file still on disk)
                FileStorage.cleanOrphanedImages(forNote: notes[index], body: notes[index].content)
            } catch {
                Log.storage.error("[NoteStore] saveDirtyNotes failed for \(noteID) — \(error)")
            }
        }
        dirtyNoteIDs.removeAll()
    }

    // MARK: - Private

    private func refreshFolders() {
        let folderNames = Set(notes.map(\.folder)).filter { !$0.isEmpty }
        let allNames = folderNames.union(diskFolderNames).sorted()

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
