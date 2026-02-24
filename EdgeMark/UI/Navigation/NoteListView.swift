import SwiftUI

struct NoteListView: View {
    @Environment(NoteStore.self) var noteStore

    var body: some View {
        VStack(spacing: 0) {
            FolderPickerView()

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
}
