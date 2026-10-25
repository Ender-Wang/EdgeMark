import CoreGraphics

/// Shared geometry for the resizable panel and its adaptive note layouts.
/// AppKit resizing and SwiftUI presentation must read the same values.
enum PanelLayoutMetrics {
    static let minimumWidth: CGFloat = 400
    static let columnBreakpoint: CGFloat = minimumWidth * 1.5
    static let minimumNavigationWidth: CGFloat = 220
    static let defaultNavigationWidth: CGFloat = 280
    static let paneSpacing: CGFloat = SurfaceMetrics.panelSectionSpacing
    static let columnResizeHitWidth: CGFloat = 8

    static let cardWidthStep: CGFloat = minimumWidth / 2
    static let cardGridSpacing: CGFloat = 8
    static let cardGridHorizontalInset: CGFloat = 8

    static func navigationWidth(preferredWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        min(max(preferredWidth, minimumNavigationWidth), availableWidth / 2)
    }

    static func navigationWidth(for availableWidth: CGFloat) -> CGFloat {
        navigationWidth(preferredWidth: defaultNavigationWidth, availableWidth: availableWidth)
    }

    static func cardColumnCount(forPanelWidth panelWidth: CGFloat) -> Int {
        max(2, Int(floor(panelWidth / cardWidthStep)))
    }
}
