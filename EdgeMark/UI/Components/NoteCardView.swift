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
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                TagDotsView(tags: note.tags)
                Spacer(minLength: 8)
                Text(note.createdAt.homeDisplayFormat)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            NoteCardSurface(
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
        .accessibilityLabel(note.title.isEmpty ? l10n["common.untitled"] : note.title)
    }
}

/// A responsive masonry grid whose thresholds derive from the panel minimum width.
/// Lazy columns preserve full-body rendering performance while the shortest-column
/// assignment avoids the empty holes created by equal-height grid rows.
struct ResponsiveNoteCardGrid<Content: View>: View {
    let panelWidth: CGFloat
    let notes: [Note]
    @ViewBuilder let content: (Note) -> Content

    private var columnCount: Int {
        PanelLayoutMetrics.cardColumnCount(forPanelWidth: panelWidth)
    }

    private var columns: [[Note]] {
        var columns = Array(repeating: [Note](), count: columnCount)
        var accumulatedHeights = Array(repeating: CGFloat.zero, count: columnCount)

        for note in notes {
            let destination = accumulatedHeights.indices.min {
                accumulatedHeights[$0] < accumulatedHeights[$1]
            } ?? 0
            columns[destination].append(note)
            accumulatedHeights[destination] += NoteCardHeightRatio.value(for: note.id)
        }

        return columns
    }

    var body: some View {
        HStack(alignment: .top, spacing: PanelLayoutMetrics.cardGridSpacing) {
            ForEach(columns.indices, id: \.self) { columnIndex in
                LazyVStack(spacing: PanelLayoutMetrics.cardGridSpacing) {
                    ForEach(columns[columnIndex]) { note in
                        content(note)
                            .aspectRatio(
                                1 / NoteCardHeightRatio.value(for: note.id),
                                contentMode: .fit,
                            )
                            .clipped()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, PanelLayoutMetrics.cardGridHorizontalInset)
        .padding(.vertical, 4)
    }
}

/// A UUID-stable preview height selected from 1.2x through 2.0x card width.
/// Never use `hashValue` here because Swift randomizes it between processes.
private enum NoteCardHeightRatio {
    static func value(for noteID: UUID) -> CGFloat {
        let bucket = noteID.uuidString.utf8.reduce(0) { partial, byte in
            (partial * 31 + Int(byte)) % 5
        }
        return 1.2 + CGFloat(bucket) * 0.2
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
