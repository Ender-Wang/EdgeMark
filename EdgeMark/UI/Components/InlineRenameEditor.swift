import SwiftUI

/// Reusable inline editor for renaming notes/folders or creating new folders.
/// Shows a "Name taken" pill overlay when the name conflicts with an existing item.
struct InlineRenameEditor: View {
    let icon: String
    var iconColor: Color = .secondary
    let placeholder: String
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isConflicting: Bool
    let iconWidth: CGFloat
    let onCommit: () -> Void
    let onCancel: () -> Void
    let onFocusLost: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: iconWidth)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .focused(isFocused)
                .onSubmit(onCommit)
                .overlay(alignment: .trailing) {
                    Text("Name taken")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                        .opacity(isConflicting ? 1 : 0)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .onExitCommand(perform: onCancel)
        .onChange(of: isFocused.wrappedValue) { _, focused in
            if !focused { onFocusLost() }
        }
    }
}
