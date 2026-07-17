import SwiftUI

extension View {
    /// Attaches note and folder move-conflict alert dialogs.
    ///
    /// The dialogs read the head of the per-conflict queue, so a batch move that produces
    /// multiple collisions surfaces them sequentially instead of dropping all but the last.
    /// When more than one conflict is queued the buttons switch to batch mode (Keep Both All /
    /// Replace All / Skip / Cancel) so the user doesn't have to decide N times for the obvious case.
    func moveConflictAlerts(noteStore: NoteStore, l10n: L10n) -> some View {
        alert(
            l10n["alert.nameConflict"],
            isPresented: Binding(
                get: { !noteStore.pendingNoteMoveConflicts.isEmpty },
                set: {
                    if !$0 {
                        noteStore.cancelAllNoteMoveConflicts()
                    }
                },
            ),
        ) {
            if noteStore.pendingNoteMoveConflicts.count > 1 {
                Button(l10n["alert.nameConflict.keepBothAll"]) {
                    noteStore.resolveAllNoteMoveConflicts(keepBoth: true)
                }
                Button(l10n["alert.nameConflict.replaceAll"], role: .destructive) {
                    noteStore.resolveAllNoteMoveConflicts(keepBoth: false)
                }
                Button(l10n["alert.nameConflict.skip"]) { noteStore.skipNoteMoveConflict() }
                Button(l10n["common.cancel"], role: .cancel) { noteStore.cancelAllNoteMoveConflicts() }
            } else {
                Button(l10n["alert.nameConflict.keepBoth"]) { noteStore.resolveNoteMoveConflict(keepBoth: true) }
                Button(l10n["alert.nameConflict.replace"]) { noteStore.resolveNoteMoveConflict(keepBoth: false) }
                Button(l10n["common.cancel"], role: .cancel) { noteStore.cancelAllNoteMoveConflicts() }
            }
        } message: {
            if let conflict = noteStore.pendingNoteMoveConflicts.first,
               let note = noteStore.notes.first(where: { $0.id == conflict.noteID })
            {
                let dest = conflict.targetFolder.isEmpty ? "/" : "/\(conflict.targetFolder)/"
                let count = noteStore.pendingNoteMoveConflicts.count
                if count > 1 {
                    Text(l10n.t("alert.nameConflict.note.batch", note.title, dest, "\(count)"))
                } else {
                    Text(l10n.t("alert.nameConflict.note", note.title, dest))
                }
            }
        }
        .alert(
            l10n["alert.nameConflict"],
            isPresented: Binding(
                get: { !noteStore.pendingFolderMoveConflicts.isEmpty },
                set: {
                    if !$0 {
                        noteStore.cancelAllFolderMoveConflicts()
                    }
                },
            ),
        ) {
            if noteStore.pendingFolderMoveConflicts.count > 1 {
                Button(l10n["alert.nameConflict.keepBothAll"]) {
                    noteStore.resolveAllFolderMoveConflicts(keepBoth: true)
                }
                Button(l10n["alert.nameConflict.replaceAll"], role: .destructive) {
                    noteStore.resolveAllFolderMoveConflicts(keepBoth: false)
                }
                Button(l10n["alert.nameConflict.skip"]) { noteStore.skipFolderMoveConflict() }
                Button(l10n["common.cancel"], role: .cancel) { noteStore.cancelAllFolderMoveConflicts() }
            } else {
                Button(l10n["alert.nameConflict.keepBoth"]) { noteStore.resolveFolderMoveConflict(keepBoth: true) }
                Button(l10n["alert.nameConflict.replace"], role: .destructive) {
                    noteStore.resolveFolderMoveConflict(keepBoth: false)
                }
                Button(l10n["common.cancel"], role: .cancel) { noteStore.cancelAllFolderMoveConflicts() }
            }
        } message: {
            if let conflict = noteStore.pendingFolderMoveConflicts.first {
                let displayName = (conflict.folderName as NSString).lastPathComponent
                let dest = conflict.targetParent.isEmpty ? "/" : "/\(conflict.targetParent)/"
                let count = noteStore.pendingFolderMoveConflicts.count
                if count > 1 {
                    Text(l10n.t("alert.nameConflict.folder.batch", displayName, dest, "\(count)"))
                } else {
                    Text(l10n.t("alert.nameConflict.folder", displayName, dest))
                }
            }
        }
    }
}
