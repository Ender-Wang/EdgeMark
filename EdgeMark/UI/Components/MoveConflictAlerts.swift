import SwiftUI

extension View {
    /// Attaches note and folder move-conflict alert dialogs.
    func moveConflictAlerts(noteStore: NoteStore) -> some View {
        alert(
            "Name Conflict",
            isPresented: Binding(
                get: { noteStore.pendingNoteMoveConflict != nil },
                set: { if !$0 { noteStore.pendingNoteMoveConflict = nil } },
            ),
        ) {
            Button("Keep Both") { noteStore.resolveNoteMoveConflict(keepBoth: true) }
            Button("Replace") { noteStore.resolveNoteMoveConflict(keepBoth: false) }
            Button("Cancel", role: .cancel) { noteStore.pendingNoteMoveConflict = nil }
        } message: {
            if let conflict = noteStore.pendingNoteMoveConflict,
               let note = noteStore.notes.first(where: { $0.id == conflict.noteID })
            {
                let dest = conflict.targetFolder.isEmpty ? "/" : "/\(conflict.targetFolder)/"
                Text("A note named \"\(note.title)\" already exists in \"\(dest)\".")
            }
        }
        .alert(
            "Name Conflict",
            isPresented: Binding(
                get: { noteStore.pendingFolderMoveConflict != nil },
                set: { if !$0 { noteStore.pendingFolderMoveConflict = nil } },
            ),
        ) {
            Button("Keep Both") { noteStore.resolveFolderMoveConflict(keepBoth: true) }
            Button("Replace", role: .destructive) { noteStore.resolveFolderMoveConflict(keepBoth: false) }
            Button("Cancel", role: .cancel) { noteStore.pendingFolderMoveConflict = nil }
        } message: {
            if let conflict = noteStore.pendingFolderMoveConflict {
                let displayName = (conflict.folderName as NSString).lastPathComponent
                let dest = conflict.targetParent.isEmpty ? "/" : "/\(conflict.targetParent)/"
                Text("A folder named \"\(displayName)\" already exists in \"\(dest)\".")
            }
        }
    }
}
