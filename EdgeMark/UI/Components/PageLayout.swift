import SwiftUI

enum PageLayoutPresentation {
    case standalone
    case embedded
}

enum PageLayoutJoinRole {
    case none
    case leading
    case trailing

    var cornerRadii: RectangleCornerRadii {
        let radius = SurfaceMetrics.panelCornerRadius
        switch self {
        case .none:
            return RectangleCornerRadii(
                topLeading: radius,
                bottomLeading: radius,
                bottomTrailing: radius,
                topTrailing: radius,
            )
        case .leading:
            return RectangleCornerRadii(topLeading: radius, bottomLeading: radius)
        case .trailing:
            return RectangleCornerRadii(bottomTrailing: radius, topTrailing: radius)
        }
    }

    var drawsTrailingDivider: Bool {
        self == .leading
    }
}

/// Shared page layout with separate header and body surfaces.
/// Pass `onSwipeBack` to enable two-finger trackpad right-swipe to go back on the header.
struct PageLayout<Header: View, Content: View>: View {
    var presentation: PageLayoutPresentation
    var joinRole: PageLayoutJoinRole
    var onSwipeBack: (() -> Void)?
    var onContentSwipeRight: (() -> Void)?
    var onContentSwipeLeft: (() -> Void)?
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    init(
        presentation: PageLayoutPresentation = .standalone,
        joinRole: PageLayoutJoinRole = .none,
        onSwipeBack: (() -> Void)? = nil,
        onContentSwipeRight: (() -> Void)? = nil,
        onContentSwipeLeft: (() -> Void)? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
    ) {
        self.presentation = presentation
        self.joinRole = joinRole
        self.onSwipeBack = onSwipeBack
        self.onContentSwipeRight = onContentSwipeRight
        self.onContentSwipeLeft = onContentSwipeLeft
        self.header = header()
        self.content = content()
    }

    var body: some View {
        let surfaceShape = UnevenRoundedRectangle(
            cornerRadii: joinRole.cornerRadii,
            style: .continuous,
        )

        VStack(spacing: SurfaceMetrics.panelSectionSpacing) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background { PanelContentSurface() }
                .clipShape(surfaceShape)
                .overlay {
                    if let onSwipeBack {
                        SwipeDetectorView(onSwipeBack: onSwipeBack)
                    }
                }
                .overlay(alignment: .trailing) {
                    if joinRole.drawsTrailingDivider {
                        joinedDivider
                    }
                }

            content
                .background { PanelContentSurface() }
                .clipShape(surfaceShape)
                .overlay {
                    if onContentSwipeRight != nil || onContentSwipeLeft != nil {
                        SwipeDetectorView(
                            onSwipeBack: onContentSwipeRight,
                            onSwipeForward: onContentSwipeLeft,
                        )
                    }
                }
                .overlay(alignment: .trailing) {
                    if joinRole.drawsTrailingDivider {
                        joinedDivider
                    }
                }
        }
        .padding(.horizontal, presentation == .standalone ? 12 : 0)
        .padding(.top, presentation == .standalone ? 8 : 0)
        .padding(.bottom, presentation == .standalone ? 12 : 0)
    }

    private var joinedDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 1)
            .allowsHitTesting(false)
    }
}
