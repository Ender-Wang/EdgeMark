import Cocoa
import SwiftUI

struct NoteListView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(AppSettings.self) var appSettings

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

    private var folderDate: (Folder) -> Date? {
        { folder in
            switch appSettings.sortBy {
            case .name: nil
            case .dateModified: folder.latestModifiedAt
            case .dateCreated: folder.earliestCreatedAt
            }
        }
    }

    private var isEmpty: Bool {
        noteStore.filteredNotes.isEmpty && childFolders.isEmpty && !isCreatingFolder
    }

    var body: some View {
        PageLayout {
            HStack {
                HeaderIconButton(
                    systemName: "chevron.left",
                    help: "Back",
                ) {
                    navigateBack()
                }

                Spacer()

                HeaderIconButton(
                    systemName: "folder.badge.plus",
                    help: "New Folder",
                ) {
                    startCreatingFolder()
                }

                HeaderIconButton(
                    systemName: "square.and.pencil",
                    help: "New Note",
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
            "Delete Folder?",
            isPresented: $showDeleteFolderConfirm,
            presenting: deletingFolderName,
        ) { folderName in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                noteStore.trashFolder(folderName)
            }
        } message: { folderName in
            let prefix = folderName + "/"
            let count = noteStore.notes.count(where: { $0.folder == folderName || $0.folder.hasPrefix(prefix) })
            if count > 0 {
                Text("\"\((folderName as NSString).lastPathComponent)\" and its \(count) note\(count == 1 ? "" : "s") will be moved to Trash.")
            } else {
                Text("\"\((folderName as NSString).lastPathComponent)\" will be deleted.")
            }
        }
        .alert(
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

    // MARK: - Folder Row with Context Menu

    @ViewBuilder
    private func folderRowWithContextMenu(folder: Folder) -> some View {
        if renamingFolderName == folder.name {
            inlineFolderRenameEditor(folderName: folder.name)
        } else {
            FolderRowView(
                name: folder.displayName,
                count: folder.noteCount,
                date: folderDate(folder),
                iconWidth: iconWidth,
            ) {
                noteStore.selectedFolder = folder
            }
            .contextMenu {
                Button("Rename") {
                    startRenamingFolder(folder.name)
                }

                folderMoveToMenu(for: folder)

                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        FileStorage.urlForFolder(folder.name),
                    ])
                }

                Divider()

                Button("Delete", role: .destructive) {
                    deletingFolderName = folder.name
                    showDeleteFolderConfirm = true
                }
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
                noteStore.selectedNote = note
            }
            .contextMenu {
                Button("Rename") {
                    startRenamingNote(note)
                }

                moveToMenu(for: note)

                Divider()

                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        FileStorage.urlForNote(note),
                    ])
                }

                Divider()

                Button("Delete", role: .destructive) {
                    noteStore.trashNote(note)
                }
            }
        }
    }

    // MARK: - Move to Menus

    @ViewBuilder
    private func moveToMenu(for note: Note) -> some View {
        let topLevel = noteStore.folders.filter(\.isTopLevel)
        let canMoveToRoot = !note.folder.isEmpty
        if canMoveToRoot || !topLevel.isEmpty {
            Menu("Move to") {
                if canMoveToRoot {
                    Button("Root") {
                        noteStore.moveNote(note, to: "")
                    }
                }
                ForEach(topLevel) { folder in
                    if folder.name != note.folder {
                        folderTreeMenuItem(folder: folder, note: note)
                    }
                }
            }
        }
    }

    private func folderTreeMenuItem(folder: Folder, note: Note) -> AnyView {
        let children = noteStore.childFolders(of: folder.name)
            .filter { $0.name != note.folder }
        if children.isEmpty {
            return AnyView(
                Button(folder.displayName) {
                    noteStore.moveNote(note, to: folder.name)
                },
            )
        } else {
            return AnyView(
                Menu(folder.displayName) {
                    Button("Move here") {
                        noteStore.moveNote(note, to: folder.name)
                    }
                    Divider()
                    ForEach(children) { child in
                        folderTreeMenuItem(folder: child, note: note)
                    }
                },
            )
        }
    }

    @ViewBuilder
    private func folderMoveToMenu(for folder: Folder) -> some View {
        let topLevel = noteStore.folders.filter(\.isTopLevel)
            .filter { $0.name != folder.name && !$0.name.hasPrefix(folder.name + "/") }
        let canMoveToRoot = !folder.isTopLevel
        if canMoveToRoot || !topLevel.isEmpty {
            Menu("Move to") {
                if canMoveToRoot {
                    Button("Root") {
                        noteStore.moveFolder(folder.name, toParent: "")
                    }
                }
                ForEach(topLevel) { target in
                    folderMoveTreeItem(target: target, movingFolder: folder)
                }
            }
        }
    }

    private func folderMoveTreeItem(target: Folder, movingFolder: Folder) -> AnyView {
        let isCurrentParent = target.name == movingFolder.parentPath
        let children = noteStore.childFolders(of: target.name)
            .filter { $0.name != movingFolder.name && !$0.name.hasPrefix(movingFolder.name + "/") }

        if isCurrentParent {
            if children.isEmpty {
                return AnyView(EmptyView())
            }
            return AnyView(
                Menu(target.displayName) {
                    ForEach(children) { child in
                        folderMoveTreeItem(target: child, movingFolder: movingFolder)
                    }
                },
            )
        }

        if children.isEmpty {
            return AnyView(
                Button(target.displayName) {
                    noteStore.moveFolder(movingFolder.name, toParent: target.name)
                },
            )
        }

        return AnyView(
            Menu(target.displayName) {
                Button("Move here") {
                    noteStore.moveFolder(movingFolder.name, toParent: target.name)
                }
                Divider()
                ForEach(children) { child in
                    folderMoveTreeItem(target: child, movingFolder: movingFolder)
                }
            },
        )
    }

    // MARK: - Inline Note Rename Editor

    private func inlineNoteRenameEditor(note: Note) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: iconWidth)

            TextField("Note title", text: $renamingNoteText)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isNoteRenameFocused)
                .onSubmit { commitNoteRename(note) }
                .overlay(alignment: .trailing) {
                    Text("Name taken")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                        .opacity(noteRenameConflicts ? 1 : 0)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .onExitCommand { cancelNoteRename() }
        .onChange(of: isNoteRenameFocused) { _, focused in
            if !focused { commitOrCancelNoteRename(note) }
        }
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
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: iconWidth)

            TextField("Folder name", text: $newFolderName)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFolderFieldFocused)
                .onSubmit { commitNewFolder() }
                .overlay(alignment: .trailing) {
                    Text("Name taken")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                        .opacity(newFolderNameConflicts ? 1 : 0)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .onExitCommand { cancelNewFolder() }
        .onChange(of: isFolderFieldFocused) { _, focused in
            if !focused {
                commitOrCancelFolder()
            }
        }
    }

    // MARK: - Inline Folder Rename Editor

    private func inlineFolderRenameEditor(folderName: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: iconWidth)

            TextField("Folder name", text: $renamingFolderText)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFolderRenameFocused)
                .onSubmit { commitFolderRename(folderName) }
                .overlay(alignment: .trailing) {
                    Text("Name taken")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                        .opacity(folderRenameConflicts ? 1 : 0)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .onExitCommand { cancelFolderRename() }
        .onChange(of: isFolderRenameFocused) { _, focused in
            if !focused { commitOrCancelFolderRename(folderName) }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No Notes")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Tap the pencil icon to create a note")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Navigation

    private func navigateBack() {
        if let parent = noteStore.selectedFolder?.parentPath, !parent.isEmpty {
            noteStore.selectedFolder = noteStore.folders.first { $0.name == parent }
                ?? Folder(name: parent, noteCount: 0)
        } else {
            noteStore.selectedFolder = nil
        }
    }

    // MARK: - Note Actions

    private func createNote() {
        let folder = noteStore.selectedFolder?.name ?? ""
        let note = noteStore.createNote(in: folder)
        noteStore.selectedNote = note
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
