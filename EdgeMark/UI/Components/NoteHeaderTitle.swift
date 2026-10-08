import SwiftUI

/// Editable note title used as the primary content in the editor header.
/// Its tooltip carries the path and, when hidden from the header, note dates.
struct NoteHeaderTitle: View {
    @Environment(AppSettings.self) private var appSettings

    let title: String
    let path: String
    let modifiedAt: Date
    let createdAt: Date
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
            .quickHoverHelp(hoverDetails)
            .accessibilityAddTraits(.isHeader)
    }

    private var hoverDetails: String {
        guard !appSettings.showNoteDatesInHeader else { return path }
        return [
            path,
            L10n.shared.t("editor.modifiedAt", modifiedAt.homeDateFormat, modifiedAt.homeTimeFormat),
            L10n.shared.t("editor.createdAt", createdAt.homeDateFormat, createdAt.homeTimeFormat),
        ].joined(separator: "\n")
    }
}

/// Path details that appear faster than the system `.help` delay.
private struct QuickHoverHelpModifier: ViewModifier {
    let text: String

    @State private var isPresented = false
    @State private var revealTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover(perform: updateHover)
            .popover(
                isPresented: $isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top,
            ) {
                Text(text)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
            .onDisappear(perform: cancelReveal)
    }

    private func updateHover(_ hovering: Bool) {
        revealTask?.cancel()

        guard hovering else {
            isPresented = false
            return
        }

        revealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            isPresented = true
        }
    }

    private func cancelReveal() {
        revealTask?.cancel()
        isPresented = false
    }
}

extension View {
    func quickHoverHelp(_ text: String) -> some View {
        modifier(QuickHoverHelpModifier(text: text))
    }
}
