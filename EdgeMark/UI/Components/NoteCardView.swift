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
            NoteCardSurface(
                isHovered: isHovered,
                isSelected: selectionPosition.isSelected,
            )
        }
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

/// A responsive card grid whose thresholds derive from the panel minimum width.
/// Flexible tracks resize directly; only a column-count change receives animation
/// from the caller so ordinary panel dragging remains attached to the pointer.
struct ResponsiveNoteCardGrid<Content: View>: View {
    let panelWidth: CGFloat
    @ViewBuilder let content: Content

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: PanelLayoutMetrics.cardGridSpacing),
            count: PanelLayoutMetrics.cardColumnCount(forPanelWidth: panelWidth),
        )
    }

    var body: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
            spacing: PanelLayoutMetrics.cardGridSpacing,
        ) {
            content
        }
        .padding(.horizontal, PanelLayoutMetrics.cardGridHorizontalInset)
        .padding(.vertical, 4)
    }
}

private struct NoteCardSurface: View {
    @Environment(AppSettings.self) private var appSettings

    let isHovered: Bool
    let isSelected: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: SurfaceMetrics.panelCornerRadius,
            style: .continuous,
        )
    }

    var body: some View {
        if #available(macOS 26.0, *), appSettings.usesLiquidGlass {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.fill(liquidGlassOverlay)
                }
        } else {
            shape.fill(classicFill)
        }
    }

    private var liquidGlassOverlay: Color {
        if isSelected {
            return Color.accentColor.opacity(isHovered ? 0.20 : 0.14)
        }
        return Color.primary.opacity(isHovered ? 0.06 : 0)
    }

    private var classicFill: Color {
        if isSelected {
            return Color.accentColor.opacity(isHovered ? 0.28 : 0.20)
        }
        return Color.primary.opacity(isHovered ? 0.07 : 0.04)
    }
}
