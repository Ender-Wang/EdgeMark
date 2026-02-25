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

    private let iconWidth: CGFloat = 22

    private var folderLabel: String {
        noteStore.selectedFolder?.name ?? ""
    }

    private var sortedNotes: [Note] {
        noteStore.sortedNotes(noteStore.filteredNotes, by: appSettings.sortBy, ascending: appSettings.sortAscending)
    }

    var body: some View {
        PageLayout {
            HStack {
                HeaderIconButton(
                    systemName: "chevron.left",
                    help: "Home",
                ) {
                    noteStore.selectedFolder = nil
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
                Text(folderLabel)
                    .font(.headline)
            }
        } content: {
            VStack(spacing: 0) {
                ZStack {
                    emptyState
                        .opacity(noteStore.filteredNotes.isEmpty && !isCreatingFolder ? 1 : 0)

                    ScrollView {
                        VStack(spacing: 0) {
                            if isCreatingFolder {
                                inlineFolderEditor
                            }

                            ForEach(sortedNotes) { note in
                                noteRowWithContextMenu(note: note)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .opacity(noteStore.filteredNotes.isEmpty && !isCreatingFolder ? 0 : 1)
                }

                Divider()
                    .padding(.horizontal, 12)

                ContentFooterBar()
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

    @ViewBuilder
    private func moveToMenu(for note: Note) -> some View {
        let otherFolders = noteStore.folders.filter { $0.name != note.folder }
        let canMoveToRoot = !note.folder.isEmpty
        if canMoveToRoot || !otherFolders.isEmpty {
            Menu("Move to") {
                if canMoveToRoot {
                    Button("Root") {
                        noteStore.moveNote(note, to: "")
                    }
                }
                ForEach(otherFolders) { folder in
                    Button(folder.name) {
                        noteStore.moveNote(note, to: folder.name)
                    }
                }
            }
        }
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

    private var inlineFolderEditor: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: iconWidth)

            TextField("Folder name", text: $newFolderName)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFolderFieldFocused)
                .onSubmit { commitNewFolder() }
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
        if trimmed.isEmpty {
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
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            noteStore.createFolder(named: trimmed)
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
        if trimmed.isEmpty {
            cancelNewFolder()
        } else {
            commitNewFolder()
        }
    }
}
