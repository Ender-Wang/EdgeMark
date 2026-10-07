import SwiftUI

/// Keeps the open note's title visible while editor content scrolls beneath it.
/// The reserved editor inset matches the overlay's occupied height, so content
/// begins below the title but can move behind its translucent surface.
struct StickyNoteTitleBar: View {
    static let editorContentInset: CGFloat = surfaceHeight + topInset

    private static let surfaceHeight: CGFloat = 44
    private static let topInset: CGFloat = 8
    private static let horizontalInset: CGFloat = 8

    @Environment(AppSettings.self) private var appSettings

    let title: String
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isEditing: Bool
    let isConflicting: Bool
    let onBeginEditing: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onFocusLost: () -> Void

    var body: some View {
        Group {
            if #available(macOS 26.0, *), appSettings.usesLiquidGlass {
                titleField
                    .glassEffect(.regular, in: titleShape)
            } else {
                titleField
                    .background(.regularMaterial, in: titleShape)
                    .overlay {
                        titleShape
                            .strokeBorder(.separator.opacity(0.45), lineWidth: 0.5)
                    }
            }
        }
        .padding(.horizontal, Self.horizontalInset)
        .padding(.top, Self.topInset)
        .accessibilityAddTraits(.isHeader)
    }

    private var titleField: some View {
        TextField("", text: $text, prompt: Text(title))
            .textFieldStyle(.plain)
            .font(.title3.weight(.semibold))
            .lineLimit(1)
            .accessibilityLabel(L10n.shared["common.noteTitlePlaceholder"])
            .focused(isFocused)
            .onSubmit(onCommit)
            .onExitCommand(perform: onCancel)
            .onChange(of: isFocused.wrappedValue) { _, focused in
                if focused {
                    onBeginEditing()
                } else if isEditing {
                    onFocusLost()
                }
            }
            .overlay(alignment: .trailing) {
                Text(L10n.shared["common.nameTaken"])
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                    .opacity(isConflicting ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: Self.surfaceHeight)
    }

    private var titleShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: SurfaceMetrics.liquidGlassControlCornerRadius,
            style: .continuous,
        )
    }
}
