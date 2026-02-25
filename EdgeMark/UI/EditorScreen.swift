import SwiftUI

struct EditorScreen: View {
    @Environment(NoteStore.self) var noteStore

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            if let note = noteStore.selectedNote {
                MarkdownEditorView(
                    noteID: note.id,
                    initialContent: note.content,
                    onContentChanged: { newContent in
                        noteStore.updateContent(for: note.id, content: newContent)
                    },
                )
            }
        }
    }

    private var backLabel: String {
        noteStore.selectedFolder != nil ? "Notes" : "Home"
    }

    private var toolbar: some View {
        HStack {
            Button(action: goBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text(backLabel)
                }
            }
            .buttonStyle(.borderless)

            Spacer()

            Menu {
                Button("Delete", role: .destructive) {
                    if let note = noteStore.selectedNote {
                        noteStore.selectedNote = nil
                        noteStore.deleteNote(note)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("More Actions")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func goBack() {
        noteStore.saveDirtyNotes()
        noteStore.selectedNote = nil
    }
}
