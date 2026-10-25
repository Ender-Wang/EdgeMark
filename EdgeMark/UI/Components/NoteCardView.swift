import SwiftUI

struct NoteCardView: View {
    @Environment(L10n.self) private var l10n

    let note: Note
    var selectionPosition: RowSelectionPosition = .none

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TagDotsView(tags: note.tags)

                Text(note.title.isEmpty ? l10n["common.untitled"] : note.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(note.createdAt.homeDisplayFormat)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }

            if note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(l10n["card.empty"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ReadOnlyMarkdownView(
                    content: note.content,
                    noteFolder: note.folder,
                    layout: .fitsContent,
                    documentID: "card-\(note.id.uuidString)",
                )
                .fixedSize(horizontal: false, vertical: true)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            PanelRowBackground(
                isHovered: isHovered,
                selectionPosition: selectionPosition.isSelected ? .single : .none,
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(note.title.isEmpty ? l10n["common.untitled"] : note.title)
    }
}
