import SwiftUI

/// Shared page layout with separate header and body surfaces.
/// Pass `onSwipeBack` to enable two-finger trackpad right-swipe to go back on the header.
struct PageLayout<Header: View, Content: View>: View {
    var onSwipeBack: (() -> Void)?
    var onContentSwipeRight: (() -> Void)?
    var onContentSwipeLeft: (() -> Void)?
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    init(
        onSwipeBack: (() -> Void)? = nil,
        onContentSwipeRight: (() -> Void)? = nil,
        onContentSwipeLeft: (() -> Void)? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
    ) {
        self.onSwipeBack = onSwipeBack
        self.onContentSwipeRight = onContentSwipeRight
        self.onContentSwipeLeft = onContentSwipeLeft
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: SurfaceMetrics.panelSectionSpacing) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background { PanelContentSurface() }
                .clipShape(RoundedRectangle(cornerRadius: SurfaceMetrics.panelCornerRadius))
                .overlay {
                    if let onSwipeBack {
                        SwipeDetectorView(onSwipeBack: onSwipeBack)
                    }
                }

            content
                .background { PanelContentSurface() }
                .clipShape(RoundedRectangle(cornerRadius: SurfaceMetrics.panelCornerRadius))
                .overlay {
                    if onContentSwipeRight != nil || onContentSwipeLeft != nil {
                        SwipeDetectorView(
                            onSwipeBack: onContentSwipeRight,
                            onSwipeForward: onContentSwipeLeft,
                        )
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}
