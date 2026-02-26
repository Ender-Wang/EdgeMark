import Cocoa
import SwiftUI

struct TrashView: View {
    @Environment(NoteStore.self) var noteStore

    @State private var deletingNote: Note?
    @State private var showDeleteConfirm = false
    @State private var showEmptyTrashConfirm = false

    private var sortedTrashedNotes: [Note] {
        noteStore.trashedNotes.sorted { a, b in
            (a.trashedAt ?? .distantPast) > (b.trashedAt ?? .distantPast)
        }
    }

    var body: some View {
        PageLayout {
            HStack {
                HeaderIconButton(
                    systemName: "chevron.left",
                    help: "Back",
                ) {
                    noteStore.showTrash = false
                }

                Spacer()

                HeaderIconButton(
                    systemName: "trash.slash",
                    help: "Empty Trash",
                ) {
                    showEmptyTrashConfirm = true
                }
                .opacity(noteStore.trashedNotes.isEmpty ? 0.3 : 1)
                .disabled(noteStore.trashedNotes.isEmpty)
            }
            .overlay {
                Text("Trash")
                    .font(.headline)
            }
        } content: {
            VStack(spacing: 0) {
                ZStack {
                    emptyState
                        .opacity(noteStore.trashedNotes.isEmpty ? 1 : 0)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(sortedTrashedNotes) { note in
                                trashedNoteRow(note: note)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .opacity(noteStore.trashedNotes.isEmpty ? 0 : 1)
                }

                Divider()
                    .padding(.horizontal, 12)

                ContentFooterBar()
            }
        }
        .alert("Empty Trash?", isPresented: $showEmptyTrashConfirm) {
            Button("Empty Trash", role: .destructive) {
                noteStore.emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = noteStore.trashedNotes.count
            Text("All \(count) note(s) will be permanently deleted. This cannot be undone.")
        }
        .alert("Delete Permanently?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let note = deletingNote {
                    noteStore.permanentlyDeleteNote(note)
                    deletingNote = nil
                }
            }
            Button("Cancel", role: .cancel) {
                deletingNote = nil
            }
        } message: {
            if let note = deletingNote {
                Text("\u{201C}\(note.title)\u{201D} will be permanently deleted. This cannot be undone.")
            }
        }
    }

    // MARK: - Trashed Note Row

    private func trashedNoteRow(note: Note) -> some View {
        TrashedNoteRowView(note: note)
            .contextMenu {
                Button("Restore") {
                    noteStore.restoreNote(note)
                }

                Divider()

                Button("Delete Permanently", role: .destructive) {
                    deletingNote = note
                    showDeleteConfirm = true
                }
            }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "trash",
            title: "Trash is Empty",
            subtitle: "Deleted notes appear here for 60 days",
        )
    }
}

// MARK: - Trashed Note Row View

private struct TrashedNoteRowView: View {
    let note: Note

    @State private var isHovered = false

    private let iconWidth: CGFloat = 22

    private var trashInfo: String {
        guard let trashedAt = note.trashedAt else { return "" }
        let days = Calendar.current.dateComponents([.day], from: trashedAt, to: Date()).day ?? 0
        let remaining = max(60 - days, 0)
        let folder = note.folder.isEmpty ? "Root" : note.folder
        if days == 0 {
            return "\(folder) \u{00B7} Trashed today \u{00B7} \(remaining)d left"
        }
        return "\(folder) \u{00B7} Trashed \(days)d ago \u{00B7} \(remaining)d left"
    }

    var body: some View {
        Button {
            // No action on tap — use context menu
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: iconWidth)

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(trashInfo)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.primary.opacity(isHovered ? 0.06 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
