import SwiftUI

/// Toggles `PanelSettings.shared.isPanelPinned`. When pinned, the icon
/// shows filled and stays accent-colored regardless of hover so the active
/// state reads at a glance.
struct PinButton: View {
    @Environment(L10n.self) private var l10n
    @State private var isPinned: Bool = PanelSettings.shared.isPanelPinned
    /// Pinning is implicit in Edge-toggle mode (the panel sticks until the
    /// activating edge is re-touched), so the button is redundant there.
    @State private var isVisible: Bool = PanelSettings.shared.dismissalMode != .toggle

    var body: some View {
        AdaptiveIconButton(
            systemName: isPinned ? "pin.fill" : "pin",
            help: isPinned ? l10n["common.unpin"] : l10n["common.pin"],
            isActive: isPinned,
        ) {
            isPinned.toggle()
            PanelSettings.shared.isPanelPinned = isPinned
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .onReceive(NotificationCenter.default.publisher(for: .panelPinStateChanged)) { _ in
            // Keep the icon in sync when pin is toggled by the Cmd-P shortcut
            // (or any path other than this button's own tap).
            isPinned = PanelSettings.shared.isPanelPinned
        }
        .onReceive(NotificationCenter.default.publisher(for: .shortcutSettingsChanged)) { _ in
            // Hide the button when dismissal mode flips to Edge-toggle (pinning
            // becomes implicit), show it again in Auto-hide.
            isVisible = PanelSettings.shared.dismissalMode != .toggle
        }
    }
}
