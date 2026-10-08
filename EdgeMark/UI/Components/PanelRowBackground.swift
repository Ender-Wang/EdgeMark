import SwiftUI

/// Shared selection and hover surface for note and folder rows.
/// Active row states adopt Liquid Glass when enabled; classic mode keeps the established fills.
struct PanelRowBackground: View {
    @Environment(AppSettings.self) private var appSettings

    let isHovered: Bool
    var isSelected = false

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: SurfaceMetrics.panelCornerRadius,
            style: .continuous,
        )
    }

    var body: some View {
        if #available(macOS 26.0, *), appSettings.usesLiquidGlass, isHovered || isSelected {
            shape
                .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear)
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            shape.fill(classicFill)
        }
    }

    private var classicFill: Color {
        if isSelected {
            return Color.accentColor.opacity(isHovered ? 0.28 : 0.20)
        }
        return Color.primary.opacity(isHovered ? 0.06 : 0)
    }
}
