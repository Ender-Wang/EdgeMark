import SwiftUI

/// Toggles `ShortcutSettings.shared.isPanelPinned`. When pinned, the icon
/// shows filled and stays accent-colored regardless of hover so the active
/// state reads at a glance.
struct PinButton: View {
    @Environment(L10n.self) private var l10n
    @State private var isPinned: Bool = ShortcutSettings.shared.isPanelPinned
    @State private var isHovered = false

    var body: some View {
        Button {
            isPinned.toggle()
            ShortcutSettings.shared.isPanelPinned = isPinned
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isPinned ? Color.accentColor : (isHovered ? .primary : .secondary))
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.primary.opacity(isHovered ? 0.1 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("p", modifiers: .command)
        .help(isPinned ? l10n["common.unpin"] : l10n["common.pin"])
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
