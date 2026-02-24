import SwiftUI

struct FolderPickerView: View {
    @Environment(NoteStore.self) var noteStore
    @State private var showNewFolder = false
    @State private var newFolderName = ""

    var body: some View {
        HStack {
            Menu {
                Button("All Notes") {
                    noteStore.selectedFolder = .allNotes
                }
                if !noteStore.folders.isEmpty {
                    Divider()
                }
                ForEach(noteStore.folders) { folder in
                    Button(folder.name) {
                        noteStore.selectedFolder = folder
                    }
                }
                Divider()
                Button("New Folder\u{2026}") {
                    showNewFolder = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text(folderLabel)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.primary)
            }
            .menuStyle(.borderlessButton)

            Spacer()

            Button(action: createNote) {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("New Note")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                noteStore.createFolder(named: newFolderName)
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
        }
    }

    private var folderLabel: String {
        noteStore.selectedFolder.name.isEmpty ? "All Notes" : noteStore.selectedFolder.name
    }

    private func createNote() {
        let note = noteStore.createNote(in: noteStore.selectedFolder.name)
        noteStore.selectedNote = note
    }
}
