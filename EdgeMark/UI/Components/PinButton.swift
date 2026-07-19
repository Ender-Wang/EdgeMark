import SwiftUI

/// Toggles `ShortcutSettings.shared.isPanelPinned`. When pinned, the icon
/// shows filled and stays accent-colored regardless of hover so the active
/// state reads at a glance.
struct PinButton: View {
    @Environment(L10n.self) private var l10n
    @State private var isPinned: Bool = ShortcutSettings.shared.isPanelPinned
    @State private var isHovered = false
    /// Pinning is implicit in Edge-toggle mode (the panel sticks until the
    /// activating edge is re-touched), so the button is redundant there.
    @State private var isVisible: Bool = ShortcutSettings.shared.dismissalMode != .toggle

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
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .help(isPinned ? l10n["common.unpin"] : l10n["common.pin"])
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelPinStateChanged)) { _ in
            // Keep the icon in sync when pin is toggled by the Cmd-P shortcut
            // (or any path other than this button's own tap).
            isPinned = ShortcutSettings.shared.isPanelPinned
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutSettingsChanged)) { _ in
            // Hide the button when dismissal mode flips to Edge-toggle (pinning
            // becomes implicit), show it again in Auto-hide.
            isVisible = ShortcutSettings.shared.dismissalMode != .toggle
        }
    }
}
