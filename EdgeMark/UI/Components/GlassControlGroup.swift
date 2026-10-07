import SwiftUI

extension EnvironmentValues {
    @Entry var isInPanelToolbarGroup: Bool = false
}

/// Coordinates nearby Liquid Glass controls on supported systems while
/// preserving the same ordinary SwiftUI layout on older macOS releases.
struct GlassControlGroup<Content: View>: View {
    @Environment(AppSettings.self) private var appSettings

    private let spacing: CGFloat?
    private let content: Content

    init(
        spacing: CGFloat? = 0,
        @ViewBuilder content: () -> Content,
    ) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *), appSettings.usesLiquidGlass {
            GlassEffectContainer(spacing: spacing) {
                content
            }
            .buttonBorderShape(.roundedRectangle)
        } else {
            content
        }
    }
}

/// Presents related panel toolbar actions as one Finder-style control island.
struct PanelToolbarGroup<Content: View>: View {
    @Environment(AppSettings.self) private var appSettings

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *), appSettings.usesLiquidGlass {
            groupContent
                .glassEffect(.regular.interactive(), in: Capsule())
                .clipShape(Capsule())
        } else {
            HStack(spacing: SurfaceMetrics.controlGroupSpacing) {
                content
            }
        }
    }

    private var groupContent: some View {
        HStack(spacing: 0) {
            content
        }
        .padding(.vertical, SurfaceMetrics.groupedControlVerticalInset)
        .environment(\.isInPanelToolbarGroup, true)
    }
}
