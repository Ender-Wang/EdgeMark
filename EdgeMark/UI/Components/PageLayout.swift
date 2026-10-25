import SwiftUI

enum PageLayoutPresentation {
    case standalone
    case embedded
}

/// Shared page layout with separate header and body surfaces.
/// Pass `onSwipeBack` to enable two-finger trackpad right-swipe to go back on the header.
struct PageLayout<Header: View, Content: View>: View {
    var presentation: PageLayoutPresentation
    var onSwipeBack: (() -> Void)?
    var onContentSwipeRight: (() -> Void)?
    var onContentSwipeLeft: (() -> Void)?
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    init(
        presentation: PageLayoutPresentation = .standalone,
        onSwipeBack: (() -> Void)? = nil,
        onContentSwipeRight: (() -> Void)? = nil,
        onContentSwipeLeft: (() -> Void)? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
    ) {
        self.presentation = presentation
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
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: SurfaceMetrics.panelCornerRadius,
                        style: .continuous,
                    ),
                )
                .overlay {
                    if let onSwipeBack {
                        SwipeDetectorView(onSwipeBack: onSwipeBack)
                    }
                }

            content
                .background { PanelContentSurface() }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: SurfaceMetrics.panelCornerRadius,
                        style: .continuous,
                    ),
                )
                .overlay {
                    if onContentSwipeRight != nil || onContentSwipeLeft != nil {
                        SwipeDetectorView(
                            onSwipeBack: onContentSwipeRight,
                            onSwipeForward: onContentSwipeLeft,
                        )
                    }
                }
        }
        .padding(.horizontal, presentation == .standalone ? 12 : 0)
        .padding(.top, presentation == .standalone ? 8 : 0)
        .padding(.bottom, presentation == .standalone ? 12 : 0)
    }
}
