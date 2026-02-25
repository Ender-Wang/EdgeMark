import Foundation

@Observable
final class NoteStore {
    // MARK: - State

    var notes: [Note] = []
    var folders: [Folder] = []
    var selectedFolder: Folder?
    var selectedNote: Note?

    /// Notes filtered by selected folder, sorted by most recently modified.
    var filteredNotes: [Note] {
        let filtered: [Note] = if let folder = selectedFolder {
            notes.filter { $0.folder == folder.name }
        } else {
            notes
        }
        return filtered.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Dirty Tracking

    private var dirtyNoteIDs: Set<UUID> = []

    // MARK: - Lifecycle

    func loadFromDisk() {
        do {
            notes = try FileStorage.loadAllNotes()
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
        // Also include empty folders on disk
        let diskFolders = (try? FileStorage.discoverFolders()) ?? []
        let allNames = folderNames.union(diskFolders).sorted()

        folders = allNames.map { name in
            Folder(name: name, noteCount: notes.count(where: { $0.folder == name }))
        }
    }

    private static func extractTitle(from content: String) -> String {
        let firstLine = content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let stripped = firstLine.drop { $0 == "#" || $0 == " " }
        return stripped.isEmpty ? "Untitled" : String(stripped)
    }
}
