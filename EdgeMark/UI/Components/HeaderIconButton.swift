import SwiftUI

/// Toolbar icon that adopts native Liquid Glass when available and preserves
/// EdgeMark's established hover treatment on older macOS releases.
struct HeaderIconButton: View {
    let systemName: String
    let help: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        AdaptiveIconButton(systemName: systemName, help: help, role: role, action: action)
    }
}

/// Shared rendering boundary for icon-only controls used throughout panel chrome.
struct AdaptiveIconButton: View {
    let systemName: String
    let help: String
    var isActive = false
    var role: ButtonRole?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        if #available(macOS 26.0, *) {
            Button(role: role, action: action) {
                iconLabel(isHovered: false)
            }
            .buttonStyle(.glass)
            .help(help)
            .accessibilityLabel(help)
        } else {
            Button(role: role, action: action) {
                iconLabel(isHovered: isHovered)
                    .background {
                        RoundedRectangle(cornerRadius: SurfaceMetrics.compactControlCornerRadius)
                            .fill(.primary.opacity(isHovered ? 0.1 : 0))
                    }
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
        }
    }

    private func iconLabel(isHovered: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: SurfaceMetrics.compactSymbolSize, weight: .medium))
            .foregroundStyle(foregroundColor(isHovered: isHovered))
            .frame(
                width: SurfaceMetrics.compactControlSize,
                height: SurfaceMetrics.compactControlSize,
            )
            .contentShape(Rectangle())
    }

    private func foregroundColor(isHovered: Bool) -> Color {
        if isActive {
            return .accentColor
        }
        if role == .destructive, isHovered {
            return .red
        }
        return isHovered ? .primary : .secondary
    }
}

/// Shared rendering boundary for compact icon menus in panel chrome.
struct AdaptiveIconMenu<MenuContent: View>: View {
    let systemName: String
    let help: String
    private let menuContent: MenuContent

    @State private var isHovered = false

    init(
        systemName: String,
        help: String,
        @ViewBuilder content: () -> MenuContent,
    ) {
        self.systemName = systemName
        self.help = help
        menuContent = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            menu(isHovered: false)
                .menuStyle(.button)
                .buttonStyle(.glass)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(help)
                .accessibilityLabel(help)
        } else {
            menu(isHovered: isHovered)
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(help)
                .accessibilityLabel(help)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
        }
    }

    private func menu(isHovered: Bool) -> some View {
        Menu {
            menuContent
        } label: {
            Image(systemName: systemName)
                .font(.system(size: SurfaceMetrics.compactSymbolSize, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(
                    width: SurfaceMetrics.compactControlSize,
                    height: SurfaceMetrics.compactControlSize,
                )
                .background {
                    if #unavailable(macOS 26.0) {
                        RoundedRectangle(cornerRadius: SurfaceMetrics.compactControlCornerRadius)
                            .fill(.primary.opacity(isHovered ? 0.1 : 0))
                    }
                }
                .contentShape(Rectangle())
        }
    }
}
