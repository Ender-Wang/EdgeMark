import Foundation

@Observable
final class NoteStore {
    // MARK: - State

    var notes: [Note] = []
    var trashedNotes: [Note] = []
    var folders: [Folder] = []
    var selectedFolder: Folder?
    var selectedNote: Note?
    var showTrash = false

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

    // MARK: - Dirty Tracking

    private var dirtyNoteIDs: Set<UUID> = []

    // MARK: - Lifecycle

    func loadFromDisk() {
        do {
            let all = try FileStorage.loadAllNotes()
            notes = all.filter { $0.trashedAt == nil }
            trashedNotes = all.filter { $0.trashedAt != nil }
            autoPurgeExpiredTrash()
            refreshFolders()
        } catch {
            print("EdgeMark: failed to load notes — \(error)")
        }
    }

    // MARK: - Note CRUD

    func createNote(in folder: String = "") -> Note {
        let now = Date()
        var note = Note(
            id: UUID(),
            title: "Untitled",
            content: "# Untitled\n\n",
            createdAt: now,
            modifiedAt: now,
            folder: folder,
        )
        do {
            let savedName = try FileStorage.writeNote(note)
            note.savedFilename = savedName
        } catch {
            print("EdgeMark: failed to write new note — \(error)")
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
            print("EdgeMark: failed to delete note — \(error)")
        }
        refreshFolders()
    }

    func moveNote(_ note: Note, to folder: String) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        do {
            try FileStorage.moveNote(note, toFolder: folder)
            notes[index].folder = folder
            notes[index].savedFilename = notes[index].filename
            refreshFolders()
        } catch {
            print("EdgeMark: failed to move note — \(error)")
        }
    }

    // MARK: - Trash

    func trashNote(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].trashedAt = Date()
        dirtyNoteIDs.remove(note.id)

        // Write trashed field to YAML immediately
        do {
            let newFilename = try FileStorage.writeNote(notes[index])
            notes[index].savedFilename = newFilename
        } catch {
            print("EdgeMark: failed to write trashed note — \(error)")
        }

        let trashedNote = notes.remove(at: index)
        trashedNotes.append(trashedNote)

        if selectedNote?.id == note.id {
            selectedNote = nil
        }
        refreshFolders()
    }

    func trashFolder(_ name: String) {
        guard !name.isEmpty else { return }

        // Trash all active notes in this folder
        let folderNotes = notes.filter { $0.folder == name }
        for note in folderNotes {
            trashNote(note)
        }

        // Navigate away if this folder was selected
        if selectedFolder?.name == name {
            selectedFolder = nil
        }
        refreshFolders()
    }

    func restoreNote(_ note: Note) {
        guard let index = trashedNotes.firstIndex(where: { $0.id == note.id }) else { return }
        trashedNotes[index].trashedAt = nil

        // Ensure the folder exists on disk (may have been deleted)
        if !trashedNotes[index].folder.isEmpty {
            do {
                try FileStorage.ensureFolderExists(trashedNotes[index].folder)
            } catch {
                print("EdgeMark: failed to ensure folder exists — \(error)")
            }
        }

        // Write updated YAML (removes trashed field)
        do {
            let newFilename = try FileStorage.writeNote(trashedNotes[index])
            trashedNotes[index].savedFilename = newFilename
        } catch {
            print("EdgeMark: failed to write restored note — \(error)")
        }

        let restoredNote = trashedNotes.remove(at: index)
        notes.append(restoredNote)
        refreshFolders()
    }

    func permanentlyDeleteNote(_ note: Note) {
        trashedNotes.removeAll { $0.id == note.id }
        do {
            try FileStorage.deleteNote(note)
        } catch {
            print("EdgeMark: failed to permanently delete note — \(error)")
        }
    }

    func emptyTrash() {
        for note in trashedNotes {
            do {
                try FileStorage.deleteNote(note)
            } catch {
                print("EdgeMark: failed to delete trashed note \(note.id) — \(error)")
            }
        }
        trashedNotes.removeAll()
    }

    /// Permanently delete notes that have been in trash for more than 60 days.
    private func autoPurgeExpiredTrash() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let expired = trashedNotes.filter { ($0.trashedAt ?? Date()) < cutoff }
        for note in expired {
            permanentlyDeleteNote(note)
        }
    }

    // MARK: - Folder CRUD

    func createFolder(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try FileStorage.ensureFolderExists(trimmed)
            refreshFolders()
        } catch {
            print("EdgeMark: failed to create folder — \(error)")
        }
    }

    func renameFolder(_ oldName: String, to newName: String) {
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldName.isEmpty, !trimmedNew.isEmpty, oldName != trimmedNew else { return }
        guard !folders.contains(where: { $0.name == trimmedNew }) else { return }

        do {
            try FileStorage.renameFolder(oldName, to: trimmedNew)
            // Update all notes (active and trashed) that were in the old folder
            for i in notes.indices where notes[i].folder == oldName {
                notes[i].folder = trimmedNew
            }
            for i in trashedNotes.indices where trashedNotes[i].folder == oldName {
                trashedNotes[i].folder = trimmedNew
            }
            if selectedFolder?.name == oldName {
                selectedFolder = Folder(name: trimmedNew, noteCount: selectedFolder?.noteCount ?? 0)
            }
            refreshFolders()
        } catch {
            print("EdgeMark: failed to rename folder — \(error)")
        }
    }

    // MARK: - Save

    func saveDirtyNotes() {
        for noteID in dirtyNoteIDs {
            guard let index = notes.firstIndex(where: { $0.id == noteID }) else { continue }
            do {
                let newFilename = try FileStorage.writeNote(notes[index])
                notes[index].savedFilename = newFilename
                if selectedNote?.id == noteID {
                    selectedNote?.savedFilename = newFilename
                }
            } catch {
                print("EdgeMark: failed to save note \(noteID) — \(error)")
            }
        }
        dirtyNoteIDs.removeAll()
    }

    // MARK: - Private

    private func refreshFolders() {
        let folderNames = Set(notes.map(\.folder)).filter { !$0.isEmpty }
        let trashedFolderNames = Set(trashedNotes.map(\.folder)).filter { !$0.isEmpty }
        let diskFolders = (try? FileStorage.discoverFolders()) ?? []
        // Show disk folders that have active notes OR are truly empty (not just trashed)
        let visibleDiskFolders = diskFolders.filter { name in
            folderNames.contains(name) || !trashedFolderNames.contains(name)
        }
        let allNames = folderNames.union(Set(visibleDiskFolders)).sorted()

        folders = allNames.map { name in
            let folderNotes = notes.filter { $0.folder == name }
            return Folder(
                name: name,
                noteCount: folderNotes.count,
                latestModifiedAt: folderNotes.map(\.modifiedAt).max(),
                earliestCreatedAt: folderNotes.map(\.createdAt).min(),
            )
        }
    }

    private static func extractTitle(from content: String) -> String {
        let firstLine = content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let stripped = firstLine.drop { $0 == "#" || $0 == " " }
        return stripped.isEmpty ? "Untitled" : String(stripped)
    }
}
