import Cocoa
import SwiftUI

struct NoteListView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(AppSettings.self) var appSettings
    @Environment(L10n.self) var l10n

    @State private var noteRename = NoteRenameCoordinator()
    @State private var folderRename = FolderRenameCoordinator()
    @FocusState private var isFolderFieldFocused: Bool
    @FocusState private var isNoteRenameFocused: Bool
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
        noteStore.filteredNotes.isEmpty && childFolders.isEmpty && !folderRename.isCreating
    }

    var body: some View {
        PageLayout(onSwipeBack: { navigateBack() }) {
            HStack {
                HeaderIconButton(
                    systemName: "chevron.left",
                    help: l10n["common.back"],
                ) {
                    navigateBack()
                }

                Spacer()

                PinButton()

                HeaderIconButton(
                    systemName: "magnifyingglass",
                    help: l10n["common.search"],
                ) {
                    noteStore.searchReturnFolder = noteStore.selectedFolder
                    noteStore.pendingSearchOnHome = true
                    noteStore.navigateToHome()
                }
                .keyboardShortcut("f", modifiers: .command)

                HeaderIconButton(
                    systemName: "folder.badge.plus",
                    help: l10n["common.newFolder"],
                ) {
                    startCreatingFolder()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                HeaderIconButton(
                    systemName: "square.and.pencil",
                    help: l10n["common.newNote"],
                ) {
                    createNote()
                }
                .keyboardShortcut("n", modifiers: .command)
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

                            if folderRename.isCreating {
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
        if folderRename.renamingFolderName == folder.name {
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
            .nsContextMenu {
                NoteListMenus.folderMenu(
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
        if noteRename.renamingNoteID == note.id {
            inlineNoteRenameEditor(note: note)
        } else {
            NoteRowView(
                note: note,
                iconWidth: iconWidth,
            ) {
                noteStore.openNote(note)
            }
            .nsContextMenu {
                NoteListMenus.noteMenu(
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
            text: $noteRename.text,
            isFocused: $isNoteRenameFocused,
            isConflicting: noteRename.isConflicting(in: noteStore),
            iconWidth: iconWidth,
            onCommit: { noteRename.commit(note: note, noteStore: noteStore) },
            onCancel: { noteRename.cancel(noteStore: noteStore) },
            onFocusLost: { noteRename.commitOrCancel(note: note, noteStore: noteStore) },
        )
    }

    // MARK: - Inline Folder Editor

    private var inlineFolderEditor: some View {
        InlineRenameEditor(
            icon: "folder.fill",
            iconColor: .accentColor,
            placeholder: l10n["common.folderNamePlaceholder"],
            text: $folderRename.creationText,
            isFocused: $isFolderFieldFocused,
            isConflicting: folderRename.isCreateConflicting(siblings: childFolders),
            iconWidth: iconWidth,
            onCommit: { folderRename.commitCreate(parent: noteStore.selectedFolder?.name ?? "", noteStore: noteStore, siblings: childFolders) },
            onCancel: { folderRename.cancelCreate() },
            onFocusLost: { folderRename.commitOrCancelCreate(parent: noteStore.selectedFolder?.name ?? "", noteStore: noteStore, siblings: childFolders) },
        )
    }

    // MARK: - Inline Folder Rename Editor

    private func inlineFolderRenameEditor(folderName: String) -> some View {
        InlineRenameEditor(
            icon: "folder.fill",
            iconColor: .accentColor,
            placeholder: l10n["common.folderNamePlaceholder"],
            text: $folderRename.renameText,
            isFocused: $isFolderRenameFocused,
            isConflicting: folderRename.isRenameConflicting(siblings: childFolders),
            iconWidth: iconWidth,
            onCommit: { folderRename.commitRename(folderName, noteStore: noteStore, siblings: childFolders) },
            onCancel: { folderRename.cancelRename() },
            onFocusLost: { folderRename.commitOrCancelRename(folderName, noteStore: noteStore, siblings: childFolders) },
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
        let note = noteStore.createNote(in: folder)
        noteRename.beginCreate(note: note)
        DispatchQueue.main.async { isNoteRenameFocused = true }
    }

    private func startRenamingNote(_ note: Note) {
        noteRename.beginRename(note)
        DispatchQueue.main.async { isNoteRenameFocused = true }
    }

    // MARK: - Folder Actions

    private func startCreatingFolder() {
        folderRename.beginCreate()
        DispatchQueue.main.async { isFolderFieldFocused = true }
    }

    // MARK: - Folder Rename Actions

    private func startRenamingFolder(_ name: String) {
        folderRename.beginRename(folderName: name)
        DispatchQueue.main.async { isFolderRenameFocused = true }
    }
}
