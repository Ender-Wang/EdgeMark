import SwiftUI

/// Editable note title used as the primary content in the editor header.
/// Its tooltip carries the path and, when hidden from the header, note dates.
struct NoteHeaderTitle: View {
    @Environment(AppSettings.self) private var appSettings

    let title: String
    let path: String
    let modifiedAt: String
    let createdAt: String
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isEditing: Bool
    let isConflicting: Bool
    let onBeginEditing: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onFocusLost: () -> Void

    var body: some View {
        TextField("", text: $text, prompt: Text(title))
            .textFieldStyle(.plain)
            .font(.title3.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityLabel(L10n.shared["common.noteTitlePlaceholder"])
            .accessibilityValue(hoverDetails)
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
            .layoutPriority(1)
            .contentShape(Rectangle())
            .help(hoverDetails)
            .accessibilityAddTraits(.isHeader)
    }

    private var hoverDetails: String {
        guard !appSettings.showNoteDatesInHeader else { return path }
        return [
            path,
            L10n.shared.t("editor.modifiedAt", modifiedAt),
            L10n.shared.t("editor.createdAt", createdAt),
        ].joined(separator: "\n")
    }
}
