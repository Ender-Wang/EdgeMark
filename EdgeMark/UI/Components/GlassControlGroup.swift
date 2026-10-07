import SwiftUI

extension EnvironmentValues {
    @Entry var isInPanelToolbarGroup: Bool = false
}

/// Coordinates nearby Liquid Glass controls on supported systems while
/// preserving the same ordinary SwiftUI layout on older macOS releases.
struct GlassControlGroup<Content: View>: View {
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
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
            .buttonBorderShape(.roundedRectangle)
        } else {
            content.buttonBorderShape(.roundedRectangle)
        }
    }
}

/// Presents related panel toolbar actions as one Finder-style control island.
struct PanelToolbarGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            groupContent
                .glassEffect(.regular.interactive(), in: ButtonBorderShape.roundedRectangle)
                .clipShape(ButtonBorderShape.roundedRectangle)
        } else {
            groupContent
                .background(.regularMaterial, in: ButtonBorderShape.roundedRectangle)
                .overlay {
                    ButtonBorderShape.roundedRectangle
                        .strokeBorder(.separator.opacity(0.45), lineWidth: 0.5)
                }
                .clipShape(ButtonBorderShape.roundedRectangle)
        }
    }

    private var groupContent: some View {
        HStack(spacing: 0) {
            content
        }
        .environment(\.isInPanelToolbarGroup, true)
        .buttonBorderShape(.roundedRectangle)
    }
}
