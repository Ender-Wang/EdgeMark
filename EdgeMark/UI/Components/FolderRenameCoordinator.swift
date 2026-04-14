import Foundation

/// Manages the inline folder create / rename flow.
/// Shared by HomeFolderView and NoteListView. Caller is responsible for
/// setting @FocusState after calling beginCreate / beginRename.
@Observable
final class FolderRenameCoordinator {
    // Create
    var isCreating = false
    var creationText: String = ""

    // Rename
    var renamingFolderName: String?
    var renameText: String = ""

    // MARK: - Create

    func beginCreate() {
        creationText = ""
        isCreating = true
    }

    func isCreateConflicting(siblings: [Folder]) -> Bool {
        let trimmed = creationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return siblings.contains { $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    func commitCreate(parent: String, noteStore: NoteStore, siblings: [Folder]) {
        guard !isCreateConflicting(siblings: siblings) else { return }
        let trimmed = creationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            noteStore.createFolder(named: trimmed, in: parent)
        }
        isCreating = false
        creationText = ""
    }

    func cancelCreate() {
        isCreating = false
        creationText = ""
    }

    func commitOrCancelCreate(parent: String, noteStore: NoteStore, siblings: [Folder]) {
        let trimmed = creationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || isCreateConflicting(siblings: siblings) {
            cancelCreate()
        } else {
            commitCreate(parent: parent, noteStore: noteStore, siblings: siblings)
        }
    }

    // MARK: - Rename

    func beginRename(folderName: String) {
        renamingFolderName = folderName
        renameText = (folderName as NSString).lastPathComponent
    }

    func isRenameConflicting(siblings: [Folder]) -> Bool {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let oldName = renamingFolderName else { return false }
        return siblings.contains {
            $0.name != oldName && $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    func commitRename(_ oldName: String, noteStore: NoteStore, siblings: [Folder]) {
        guard !isRenameConflicting(siblings: siblings) else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldDisplayName = (oldName as NSString).lastPathComponent
        if !trimmed.isEmpty, trimmed != oldDisplayName {
            noteStore.renameFolder(oldName, to: trimmed)
        }
        renamingFolderName = nil
        renameText = ""
    }

    func cancelRename() {
        renamingFolderName = nil
        renameText = ""
    }

    func commitOrCancelRename(_ oldName: String, noteStore: NoteStore, siblings: [Folder]) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || isRenameConflicting(siblings: siblings) {
            cancelRename()
        } else {
            commitRename(oldName, noteStore: noteStore, siblings: siblings)
        }
    }
}
