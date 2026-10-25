import CoreGraphics

/// Shared geometry for the resizable panel and its adaptive note layouts.
/// AppKit resizing and SwiftUI presentation must read the same values.
enum PanelLayoutMetrics {
    static let minimumWidth: CGFloat = 400
    static let columnBreakpoint: CGFloat = minimumWidth * 1.5
    static let navigationFraction: CGFloat = 0.38
    static let minimumNavigationWidth: CGFloat = 220
    static let maximumNavigationWidth: CGFloat = 320
    static let paneSpacing: CGFloat = SurfaceMetrics.panelSectionSpacing

    static func navigationWidth(for availableWidth: CGFloat) -> CGFloat {
        min(
            max(availableWidth * navigationFraction, minimumNavigationWidth),
            maximumNavigationWidth,
        )
    }
}
