import CoreGraphics

/// Shared measurements for panel chrome and compact functional controls.
/// Content-specific spacing remains owned by the view that renders that content.
enum SurfaceMetrics {
    static let panelCornerRadius: CGFloat = 10
    static let compactControlCornerRadius: CGFloat = 6
    static let compactControlSize: CGFloat = 28
    static let compactSymbolSize: CGFloat = 16
    static let controlGroupSpacing: CGFloat = 8
}
