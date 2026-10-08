import SwiftUI

/// Read-only preview body for the peek window. Renders a `Note` via the
/// engine-backed `ReadOnlyMarkdownView`, or a `Folder` as a compact
/// child-note list (header + rows styled like `NoteRowView`).
struct PeekContentView: View {
    @Environment(L10n.self) var l10n
    let content: PeekContent

    var body: some View {
        switch content {
        case let .note(note):
            notePreview(note)
        case let .folder(folder, subfolders, notes):
            folderPreview(folder: folder, subfolders: subfolders, notes: notes)
        }
    }

    // MARK: - Note

    private func notePreview(_ note: Note) -> some View {
        ReadOnlyMarkdownView(content: note.content, noteFolder: note.folder)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Folder

    private func folderPreview(folder: Folder, subfolders: [Folder], notes: [Note]) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(folder.color?.color ?? Color.accentColor)
                Text(folder.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(folder.noteCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if subfolders.isEmpty, notes.isEmpty {
                emptyFolderPlaceholder
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Subfolders
                        ForEach(subfolders) { subfolder in
                            subfolderRow(subfolder)
                            Divider()
                                .padding(.horizontal, 16)
                        }
                        // Notes
                        ForEach(notes) { note in
                            folderNoteRow(note)
                            if note.id != notes.last?.id {
                                Divider()
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Compact row for a subfolder inside a folder preview.
    private func subfolderRow(_ subfolder: Folder) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(subfolder.color?.color ?? Color.accentColor)
                .frame(width: 22)

            Text(subfolder.displayName)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Text("\(subfolder.noteCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyFolderPlaceholder: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 32)
            Image(systemName: "folder")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(l10n["peek.emptyFolder"])
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Compact row for a child note inside a folder preview. Read-only — no
    /// click handler, no hover highlight — but matches the NoteRowView look
    /// so the preview reads as the same list the user would see on open.
    private func folderNoteRow(_ note: Note) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "text.document")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    TagDotsView(tags: note.tags)
                    Text(note.title.isEmpty ? l10n["common.untitled"] : note.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(note.modifiedAt.homeDisplayFormat)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if !note.previewText.isEmpty {
                    Text(note.previewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
