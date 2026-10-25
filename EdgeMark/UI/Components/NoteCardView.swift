import SwiftUI

struct NoteCardView: View {
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

    let note: Note
    var selectionPosition: RowSelectionPosition = .none
    var rename: RenameConfiguration?

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TagDotsView(tags: note.tags)

                if let rename {
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
                } else {
                    Text(note.title.isEmpty ? l10n["common.untitled"] : note.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

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
