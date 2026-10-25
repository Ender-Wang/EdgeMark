import SwiftUI

/// A masonry folder card that keeps folder identity prominent while offering a
/// lightweight glance at recent notes without constructing nested Markdown views.
struct FolderCardView: View {
    struct RenameConfiguration {
        let placeholder: String
        let text: Binding<String>
        let isFocused: FocusState<Bool>.Binding
        let validationMessage: String?
        let onCommit: () -> Void
        let onCancel: () -> Void
        let onFocusLost: () -> Void
    }

    @Environment(L10n.self) private var l10n

    let folder: Folder
    let previewNotes: [Note]
    var date: Date?
    var selectionPosition: RowSelectionPosition = .none
    var rename: RenameConfiguration?

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                folderIcon

                if let rename {
                    renameField(rename)
                } else {
                    Text(folder.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            if let date {
                Text(date.homeDisplayFormat)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if previewNotes.isEmpty {
                Text(l10n["peek.emptyFolder"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 8),
                        count: 2,
                    ),
                    spacing: 8,
                ) {
                    ForEach(previewNotes.prefix(4)) { note in
                        FolderNotePreviewTile(note: note)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            MasonryCardSurface(
                isHovered: isHovered,
                isSelected: selectionPosition.isSelected,
            )
        }
        .contentShape(Rectangle())
        .clipped()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(folder.displayName)
    }

    private var folderIcon: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(folder.color?.color ?? Color.accentColor)

            if folder.noteCount > 0 {
                FolderCountBadge(count: folder.noteCount)
                    .offset(x: 4, y: -3)
            }
        }
        .frame(width: 22)
    }

    private func renameField(_ rename: RenameConfiguration) -> some View {
        TextField(rename.placeholder, text: rename.text)
            .textFieldStyle(.plain)
            .font(.headline)
            .focused(rename.isFocused)
            .onSubmit(rename.onCommit)
            .onExitCommand(perform: rename.onCancel)
            .onChange(of: rename.isFocused.wrappedValue) { _, focused in
                if !focused {
                    rename.onFocusLost()
                }
            }
            .overlay(alignment: .trailing) {
                if let message = rename.validationMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            .background.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: 4),
                        )
                }
            }
    }
}

private struct FolderNotePreviewTile: View {
    @Environment(L10n.self) private var l10n

    let note: Note

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    TagDotsView(tags: note.tags)

                    Text(note.title.isEmpty ? l10n["common.untitled"] : note.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if !note.previewText.isEmpty {
                        Text(note.previewText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    Spacer(minLength: 0)
                }
                .padding(8)
            }
            .background(Color.primary.opacity(0.05), in: shape)
            .clipShape(shape)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(note.title.isEmpty ? l10n["common.untitled"] : note.title)
    }
}
