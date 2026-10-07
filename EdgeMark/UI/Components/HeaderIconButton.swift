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
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.isInPanelToolbarGroup) private var isInPanelToolbarGroup

    let systemName: String
    let help: String
    var isActive = false
    var role: ButtonRole?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        if isInPanelToolbarGroup {
            Button(role: role, action: action) {
                groupedIconLabel(isHovered: isHovered)
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
            .onHover(perform: updateHover)
        } else if #available(macOS 26.0, *), appSettings.usesLiquidGlass {
            Button(role: role, action: action) {
                iconLabel(isHovered: false)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .help(help)
            .accessibilityLabel(help)
        } else {
            Button(role: role, action: action) {
                iconLabel(isHovered: isHovered)
                    .background {
                        RoundedRectangle(cornerRadius: SurfaceMetrics.classicControlCornerRadius)
                            .fill(.primary.opacity(isHovered ? 0.1 : 0))
                    }
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
            .onHover(perform: updateHover)
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

    private func groupedIconLabel(isHovered: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: SurfaceMetrics.compactSymbolSize, weight: .medium))
            .foregroundStyle(foregroundColor(isHovered: isHovered))
            .frame(
                width: SurfaceMetrics.groupedControlWidth,
                height: SurfaceMetrics.compactControlSize,
            )
            .background {
                RoundedRectangle(
                    cornerRadius: SurfaceMetrics.liquidGlassControlCornerRadius,
                    style: .continuous,
                )
                .fill(.primary.opacity(isHovered ? 0.1 : 0))
            }
            .padding(.horizontal, SurfaceMetrics.groupedControlHorizontalInset)
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

    private func updateHover(_ hovering: Bool) {
        withAnimation(.easeInOut(duration: 0.15)) {
            isHovered = hovering
        }
    }
}

/// Shared rendering boundary for compact icon menus in panel chrome.
struct AdaptiveIconMenu<MenuContent: View>: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.isInPanelToolbarGroup) private var isInPanelToolbarGroup

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
        if isInPanelToolbarGroup {
            menu(isHovered: isHovered, fillsGroupSegment: true)
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(help)
                .accessibilityLabel(help)
                .onHover(perform: updateHover)
        } else if #available(macOS 26.0, *), appSettings.usesLiquidGlass {
            menu(isHovered: false, fillsGroupSegment: false)
                .menuStyle(.button)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(help)
                .accessibilityLabel(help)
        } else {
            menu(isHovered: isHovered, fillsGroupSegment: false)
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(help)
                .accessibilityLabel(help)
                .onHover(perform: updateHover)
        }
    }

    private func menu(isHovered: Bool, fillsGroupSegment: Bool) -> some View {
        Menu {
            menuContent
        } label: {
            Image(systemName: systemName)
                .font(.system(size: SurfaceMetrics.compactSymbolSize, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(
                    width: fillsGroupSegment
                        ? SurfaceMetrics.groupedControlWidth
                        : SurfaceMetrics.compactControlSize,
                    height: SurfaceMetrics.compactControlSize,
                )
                .background {
                    if fillsGroupSegment {
                        RoundedRectangle(
                            cornerRadius: SurfaceMetrics.liquidGlassControlCornerRadius,
                            style: .continuous,
                        )
                        .fill(.primary.opacity(isHovered ? 0.1 : 0))
                    } else if !appSettings.usesLiquidGlass {
                        RoundedRectangle(cornerRadius: SurfaceMetrics.classicControlCornerRadius)
                            .fill(.primary.opacity(isHovered ? 0.1 : 0))
                    }
                }
                .padding(
                    .horizontal,
                    fillsGroupSegment ? SurfaceMetrics.groupedControlHorizontalInset : 0,
                )
                .contentShape(Rectangle())
        }
    }

    private func updateHover(_ hovering: Bool) {
        withAnimation(.easeInOut(duration: 0.15)) {
            isHovered = hovering
        }
    }
}
