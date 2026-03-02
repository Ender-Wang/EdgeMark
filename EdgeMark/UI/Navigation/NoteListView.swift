import Cocoa
import SwiftUI

struct NoteListView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(AppSettings.self) var appSettings
    @Environment(L10n.self) var l10n

    // Folder creation
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @FocusState private var isFolderFieldFocused: Bool

    // Note rename
    @State private var renamingNoteID: UUID?
    @State private var renamingNoteText = ""
    @FocusState private var isNoteRenameFocused: Bool

    // Folder rename
    @State private var renamingFolderName: String?
    @State private var renamingFolderText = ""
    @FocusState private var isFolderRenameFocused: Bool

    // Folder delete confirmation
    @State private var deletingFolderName: String?
    @State private var showDeleteFolderConfirm = false

    private let iconWidth: CGFloat = 22

    private var folderLabel: String {
        noteStore.selectedFolder?.displayName ?? ""
    }

    private var folderPath: String {
        guard let name = noteStore.selectedFolder?.name else { return "/" }
        return "/\(name)/"
    }

    private var sortedNotes: [Note] {
        noteStore.sortedNotes(noteStore.filteredNotes, by: appSettings.sortBy, ascending: appSettings.sortAscending)
    }

    private var childFolders: [Folder] {
        guard let parent = noteStore.selectedFolder?.name else { return [] }
        return noteStore.sortedFolders(
            noteStore.childFolders(of: parent),
            by: appSettings.sortBy,
            ascending: appSettings.sortAscending,
        )
    }

    private var isEmpty: Bool {
        noteStore.filteredNotes.isEmpty && childFolders.isEmpty && !isCreatingFolder
    }

    var body: some View {
        PageLayout {
            HStack {
                HeaderIconButton(
                    systemName: "chevron.left",
                    help: l10n["common.back"],
                ) {
                    navigateBack()
                }

                Spacer()

                HeaderIconButton(
                    systemName: "folder.badge.plus",
                    help: l10n["common.newFolder"],
                ) {
                    startCreatingFolder()
                }

                HeaderIconButton(
                    systemName: "square.and.pencil",
                    help: l10n["common.newNote"],
                ) {
                    createNote()
                }
            }
            .overlay {
                HStack(spacing: 4) {
                    Text(folderLabel)
                        .font(.headline)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Text(folderPath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.leading, 40)
                .padding(.trailing, 75)
                .help(folderPath)
            }
        } content: {
            VStack(spacing: 0) {
                ZStack {
                    emptyState
                        .opacity(isEmpty ? 1 : 0)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(childFolders) { folder in
                                folderRowWithContextMenu(folder: folder)
                            }

                            if isCreatingFolder {
                                inlineFolderEditor
                            }

                            if !childFolders.isEmpty, !sortedNotes.isEmpty {
                                Divider()
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                            }

                            ForEach(sortedNotes) { note in
                                noteRowWithContextMenu(note: note)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .opacity(isEmpty ? 0 : 1)
                }

                Divider()
                    .padding(.horizontal, 12)

                ContentFooterBar()
            }
        }
        .alert(
            l10n["alert.deleteFolder.title"],
            isPresented: $showDeleteFolderConfirm,
            presenting: deletingFolderName,
        ) { folderName in
            Button(l10n["common.cancel"], role: .cancel) {}
            Button(l10n["common.delete"], role: .destructive) {
                noteStore.trashFolder(folderName)
            }
        } message: { folderName in
            let displayName = (folderName as NSString).lastPathComponent
            let prefix = folderName + "/"
            let count = noteStore.notes.count(where: { $0.folder == folderName || $0.folder.hasPrefix(prefix) })
            if count > 0 {
                Text(l10n.t("alert.deleteFolder.withNotes", displayName, "\(count)"))
            } else {
                Text(l10n.t("alert.deleteFolder.empty", displayName))
            }
        }
        .moveConflictAlerts(noteStore: noteStore, l10n: l10n)
    }

    // MARK: - Folder Row with Context Menu

    @ViewBuilder
    private func folderRowWithContextMenu(folder: Folder) -> some View {
        if renamingFolderName == folder.name {
            inlineFolderRenameEditor(folderName: folder.name)
        } else {
            FolderRowView(
                name: folder.displayName,
                count: folder.noteCount,
                date: appSettings.folderDate(for: folder),
                iconWidth: iconWidth,
            ) {
                noteStore.navigateToSubfolder(folder)
            }
            .contextMenu {
                NoteListMenus.folderContextMenuItems(
                    folder: folder,
                    noteStore: noteStore,
                    l10n: l10n,
                    onRename: { startRenamingFolder(folder.name) },
                    onDelete: {
                        deletingFolderName = folder.name
                        showDeleteFolderConfirm = true
                    },
                )
            }
        }
    }

    // MARK: - Note Row with Context Menu

    @ViewBuilder
    private func noteRowWithContextMenu(note: Note) -> some View {
        if renamingNoteID == note.id {
            inlineNoteRenameEditor(note: note)
        } else {
            NoteRowView(
                note: note,
                iconWidth: iconWidth,
            ) {
                noteStore.openNote(note)
            }
            .contextMenu {
                NoteListMenus.noteContextMenuItems(
                    note: note,
                    noteStore: noteStore,
                    l10n: l10n,
                    onRename: { startRenamingNote(note) },
                )
            }
        }
    }

    // MARK: - Inline Note Rename Editor

    private func inlineNoteRenameEditor(note: Note) -> some View {
        InlineRenameEditor(
            icon: "doc.text",
            placeholder: l10n["common.noteTitlePlaceholder"],
            text: $renamingNoteText,
            isFocused: $isNoteRenameFocused,
            isConflicting: noteRenameConflicts,
            iconWidth: iconWidth,
            onCommit: { commitNoteRename(note) },
            onCancel: { cancelNoteRename() },
            onFocusLost: { commitOrCancelNoteRename(note) },
        )
    }

    // MARK: - Inline Folder Editor

    private var noteRenameConflicts: Bool {
        let trimmed = renamingNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let noteID = renamingNoteID else { return false }
        let folder = noteStore.notes.first(where: { $0.id == noteID })?.folder ?? ""
        return noteStore.noteTitleExists(trimmed, in: folder, excluding: noteID)
    }

    private var newFolderNameConflicts: Bool {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return childFolders.contains {
            $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private var folderRenameConflicts: Bool {
        let trimmed = renamingFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let oldName = renamingFolderName else { return false }
        return childFolders.contains {
            $0.name != oldName
                && $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private var inlineFolderEditor: some View {
        InlineRenameEditor(
            icon: "folder.fill",
            iconColor: .accentColor,
            placeholder: l10n["common.folderNamePlaceholder"],
            text: $newFolderName,
            isFocused: $isFolderFieldFocused,
            isConflicting: newFolderNameConflicts,
            iconWidth: iconWidth,
            onCommit: { commitNewFolder() },
            onCancel: { cancelNewFolder() },
            onFocusLost: { commitOrCancelFolder() },
        )
    }

    // MARK: - Inline Folder Rename Editor

    private func inlineFolderRenameEditor(folderName: String) -> some View {
        InlineRenameEditor(
            icon: "folder.fill",
            iconColor: .accentColor,
            placeholder: l10n["common.folderNamePlaceholder"],
            text: $renamingFolderText,
            isFocused: $isFolderRenameFocused,
            isConflicting: folderRenameConflicts,
            iconWidth: iconWidth,
            onCommit: { commitFolderRename(folderName) },
            onCancel: { cancelFolderRename() },
            onFocusLost: { commitOrCancelFolderRename(folderName) },
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "note.text",
            title: l10n["noteList.empty.title"],
            subtitle: l10n["noteList.empty.subtitle"],
        )
    }

    // MARK: - Navigation

    private func navigateBack() {
        noteStore.navigateBack()
    }

    // MARK: - Note Actions

    private func createNote() {
        let folder = noteStore.selectedFolder?.name ?? ""
        noteStore.createAndOpenNote(in: folder)
    }

    private func startRenamingNote(_ note: Note) {
        renamingNoteID = note.id
        renamingNoteText = note.title
        DispatchQueue.main.async {
            isNoteRenameFocused = true
        }
    }

    private func commitNoteRename(_ note: Note) {
        guard !noteRenameConflicts else { return }
        let trimmed = renamingNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != note.title {
            noteStore.renameNote(note, to: trimmed)
        }
        renamingNoteID = nil
        renamingNoteText = ""
    }

    private func cancelNoteRename() {
        renamingNoteID = nil
        renamingNoteText = ""
    }

    private func commitOrCancelNoteRename(_ note: Note) {
        let trimmed = renamingNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || noteRenameConflicts {
            cancelNoteRename()
        } else {
            commitNoteRename(note)
        }
    }

    // MARK: - Folder Actions

    private func startCreatingFolder() {
        newFolderName = ""
        isCreatingFolder = true
        DispatchQueue.main.async {
            isFolderFieldFocused = true
        }
    }

    private func commitNewFolder() {
        guard !newFolderNameConflicts else { return }
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let parent = noteStore.selectedFolder?.name ?? ""
            noteStore.createFolder(named: trimmed, in: parent)
        }
        isCreatingFolder = false
        newFolderName = ""
    }

    private func cancelNewFolder() {
        isCreatingFolder = false
        newFolderName = ""
    }

    private func commitOrCancelFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || newFolderNameConflicts {
            cancelNewFolder()
        } else {
            commitNewFolder()
        }
    }

    // MARK: - Folder Rename Actions

    private func startRenamingFolder(_ name: String) {
        renamingFolderName = name
        renamingFolderText = (name as NSString).lastPathComponent
        DispatchQueue.main.async {
            isFolderRenameFocused = true
        }
    }

    private func commitFolderRename(_ oldName: String) {
        guard !folderRenameConflicts else { return }
        let trimmed = renamingFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldDisplayName = (oldName as NSString).lastPathComponent
        if !trimmed.isEmpty, trimmed != oldDisplayName {
            noteStore.renameFolder(oldName, to: trimmed)
        }
        renamingFolderName = nil
        renamingFolderText = ""
    }

    private func cancelFolderRename() {
        renamingFolderName = nil
        renamingFolderText = ""
    }

    private func commitOrCancelFolderRename(_ oldName: String) {
        let trimmed = renamingFolderText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || folderRenameConflicts {
            cancelFolderRename()
        } else {
            commitFolderRename(oldName)
        }
    }
}
