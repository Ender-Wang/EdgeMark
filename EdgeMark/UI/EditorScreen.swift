import SwiftUI

struct EditorScreen: View {
    @Environment(NoteStore.self) var noteStore
    @State private var showDeleteConfirm = false
    /// Cached content passed to the editor — only updates when note ID changes,
    /// NOT on every save cycle, to prevent WKWebView re-creation.
    @State private var editorContent: String = ""
    @State private var editorNoteID: UUID?

    private var backLabel: String {
        noteStore.selectedFolder?.name ?? "Home"
    }

    var body: some View {
        PageLayout {
            headerContent
        } content: {
            if let note = noteStore.selectedNote {
                MarkdownEditorView(
                    noteID: note.id,
                    initialContent: editorContent,
                    onContentChanged: { newContent in
                        noteStore.updateContent(for: note.id, content: newContent)
                    },
                )
                .onChange(of: note.id, initial: true) {
                    guard editorNoteID != note.id else { return }
                    editorNoteID = note.id
                    editorContent = note.content
                }
            }
        }
        .alert("Delete Note?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let note = noteStore.selectedNote {
                    noteStore.selectedNote = nil
                    noteStore.deleteNote(note)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var headerContent: some View {
        if let note = noteStore.selectedNote {
            VStack(spacing: 4) {
                HStack {
                    HeaderIconButton(
                        systemName: "chevron.left",
                        help: backLabel,
                    ) {
                        goBack()
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                            .font(.headline)
                            .lineLimit(1)

                        Text(note.displayDirectory)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    DeleteIconButton {
                        showDeleteConfirm = true
                    }
                }

                HStack(spacing: 12) {
                    DateLabelView(
                        systemName: "clock",
                        date: note.modifiedAt.homeDisplayFormat,
                        tooltip: "Modified at \(note.modifiedAt.homeDisplayFormat)",
                    )

                    DateLabelView(
                        systemName: "calendar",
                        date: note.createdAt.homeDisplayFormat,
                        tooltip: "Created at \(note.createdAt.homeDisplayFormat)",
                    )
                }
            }
        }
    }

    private func goBack() {
        noteStore.saveDirtyNotes()
        noteStore.selectedNote = nil
    }
}

// MARK: - Delete Icon Button

/// Trash icon that turns red on hover.
private struct DeleteIconButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isHovered ? .red : .secondary)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.primary.opacity(isHovered ? 0.1 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Delete Note")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Date Label View

/// Icon + date text in a compact row with hover tooltip.
private struct DateLabelView: View {
    let systemName: String
    let date: String
    let tooltip: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemName)
            Text(date)
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .contentShape(Rectangle())
        .help(tooltip)
    }
}
