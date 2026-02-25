import SwiftUI

struct NoteListView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(AppSettings.self) var appSettings

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
                        .opacity(noteStore.filteredNotes.isEmpty ? 1 : 0)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(sortedNotes) { note in
                                NoteRowView(
                                    note: note,
                                    iconWidth: 22,
                                ) {
                                    noteStore.selectedNote = note
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .opacity(noteStore.filteredNotes.isEmpty ? 0 : 1)
                }

                Divider()
                    .padding(.horizontal, 12)

                ContentFooterBar()
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

    private func createNote() {
        let folder = noteStore.selectedFolder?.name ?? ""
        let note = noteStore.createNote(in: folder)
        noteStore.selectedNote = note
    }
}
