import SwiftUI

/// Shared two-section card layout used across all screens.
/// Header and content are each wrapped in a rounded VisualEffectView card.
struct PageLayout<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 8) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background { VisualEffectView() }
                .clipShape(RoundedRectangle(cornerRadius: 10))

            content
                .background { VisualEffectView() }
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}
