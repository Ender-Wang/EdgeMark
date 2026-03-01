import SwiftUI

extension View {
    /// Attaches note and folder move-conflict alert dialogs.
    func moveConflictAlerts(noteStore: NoteStore, l10n: L10n) -> some View {
        alert(
            l10n["alert.nameConflict"],
            isPresented: Binding(
                get: { noteStore.pendingNoteMoveConflict != nil },
                set: { if !$0 { noteStore.pendingNoteMoveConflict = nil } },
            ),
        ) {
            Button(l10n["alert.nameConflict.keepBoth"]) { noteStore.resolveNoteMoveConflict(keepBoth: true) }
            Button(l10n["alert.nameConflict.replace"]) { noteStore.resolveNoteMoveConflict(keepBoth: false) }
            Button(l10n["common.cancel"], role: .cancel) { noteStore.pendingNoteMoveConflict = nil }
        } message: {
            if let conflict = noteStore.pendingNoteMoveConflict,
               let note = noteStore.notes.first(where: { $0.id == conflict.noteID })
            {
                let dest = conflict.targetFolder.isEmpty ? "/" : "/\(conflict.targetFolder)/"
                Text(l10n.t("alert.nameConflict.note", note.title, dest))
            }
        }
        .alert(
            l10n["alert.nameConflict"],
            isPresented: Binding(
                get: { noteStore.pendingFolderMoveConflict != nil },
                set: { if !$0 { noteStore.pendingFolderMoveConflict = nil } },
            ),
        ) {
            Button(l10n["alert.nameConflict.keepBoth"]) { noteStore.resolveFolderMoveConflict(keepBoth: true) }
            Button(l10n["alert.nameConflict.replace"], role: .destructive) { noteStore.resolveFolderMoveConflict(keepBoth: false) }
            Button(l10n["common.cancel"], role: .cancel) { noteStore.pendingFolderMoveConflict = nil }
        } message: {
            if let conflict = noteStore.pendingFolderMoveConflict {
                let displayName = (conflict.folderName as NSString).lastPathComponent
                let dest = conflict.targetParent.isEmpty ? "/" : "/\(conflict.targetParent)/"
                Text(l10n.t("alert.nameConflict.folder", displayName, dest))
            }
        }
    }
}
