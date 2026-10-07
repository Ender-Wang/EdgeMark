import SwiftUI

/// Coordinates nearby Liquid Glass controls on supported systems while
/// preserving the same ordinary SwiftUI layout on older macOS releases.
struct GlassControlGroup<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    init(
        spacing: CGFloat? = SurfaceMetrics.controlGroupSpacing,
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
        } else {
            content
        }
    }
}
