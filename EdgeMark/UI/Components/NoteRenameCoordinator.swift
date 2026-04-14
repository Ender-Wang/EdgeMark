import Foundation

/// Manages the inline note rename / create-and-name flow.
/// Shared by HomeFolderView and NoteListView. Caller is responsible for
/// setting @FocusState after calling beginCreate / beginRename.
@Observable
final class NoteRenameCoordinator {
    var renamingNoteID: UUID?
    var text: String = ""
    private(set) var newlyCreatedNoteID: UUID?

    // MARK: - Begin

    func beginCreate(note: Note) {
        newlyCreatedNoteID = note.id
        renamingNoteID = note.id
        text = ""
    }

    func beginRename(_ note: Note) {
        renamingNoteID = note.id
        text = note.title
    }

    // MARK: - Conflict check

    func isConflicting(in noteStore: NoteStore) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let noteID = renamingNoteID else { return false }
        let folder = noteStore.notes.first(where: { $0.id == noteID })?.folder ?? ""
        return noteStore.noteTitleExists(trimmed, in: folder, excluding: noteID)
    }

    // MARK: - Commit / Cancel

    func commit(note: Note, noteStore: NoteStore) {
        guard !isConflicting(in: noteStore) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != note.title {
            noteStore.renameNote(note, to: trimmed)
        }
        let isNew = newlyCreatedNoteID == note.id
        clear()
        if isNew, let opened = noteStore.notes.first(where: { $0.id == note.id }) {
            noteStore.openNote(opened)
        }
    }

    func cancel(noteStore: NoteStore) {
        if let id = newlyCreatedNoteID, let note = noteStore.notes.first(where: { $0.id == id }) {
            noteStore.deleteNote(note)
        }
        clear()
    }

    func commitOrCancel(note: Note, noteStore: NoteStore) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNew = newlyCreatedNoteID == note.id
        if (trimmed.isEmpty && !isNew) || isConflicting(in: noteStore) {
            cancel(noteStore: noteStore)
        } else {
            commit(note: note, noteStore: noteStore)
        }
    }

    // MARK: - Private

    private func clear() {
        renamingNoteID = nil
        text = ""
        newlyCreatedNoteID = nil
    }
}
