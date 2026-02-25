import SwiftUI

struct NoteListView: View {
    @Environment(NoteStore.self) var noteStore

    private var folderLabel: String {
        guard let folder = noteStore.selectedFolder else { return "All Notes" }
        return folder.name.isEmpty ? "All Notes" : folder.name
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            ZStack {
                emptyState
                    .opacity(noteStore.filteredNotes.isEmpty ? 1 : 0)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(noteStore.filteredNotes) { note in
                            NoteCardView(note: note)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    noteStore.selectedNote = note
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
                .opacity(noteStore.filteredNotes.isEmpty ? 0 : 1)
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button(action: { noteStore.selectedFolder = nil }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Folders")
                }
            }
            .buttonStyle(.borderless)

            Spacer()

            Button(action: createNote) {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("New Note")
        }
        .overlay {
            Text(folderLabel)
                .font(.headline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No Notes")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Tap + to create one")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func createNote() {
        let folder = noteStore.selectedFolder?.name ?? ""
        let note = noteStore.createNote(in: folder)
        noteStore.selectedNote = note
    }
}
