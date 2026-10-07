import SwiftUI

/// Keeps the open note's title visible while editor content scrolls beneath it.
/// The reserved editor inset matches the overlay's occupied height, so content
/// begins below the title but can move behind its translucent surface.
struct StickyNoteTitleBar: View {
    static let editorContentInset: CGFloat = surfaceHeight + topInset

    private static let surfaceHeight: CGFloat = 44
    private static let topInset: CGFloat = 8
    private static let horizontalInset: CGFloat = 8

    @Environment(AppSettings.self) private var appSettings

    let title: String

    var body: some View {
        Group {
            if #available(macOS 26.0, *), appSettings.usesLiquidGlass {
                titleLabel
                    .glassEffect(.regular, in: titleShape)
            } else {
                titleLabel
                    .background(.regularMaterial, in: titleShape)
                    .overlay {
                        titleShape
                            .strokeBorder(.separator.opacity(0.45), lineWidth: 0.5)
                    }
            }
        }
        .padding(.horizontal, Self.horizontalInset)
        .padding(.top, Self.topInset)
        .accessibilityAddTraits(.isHeader)
    }

    private var titleLabel: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: Self.surfaceHeight)
    }

    private var titleShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: SurfaceMetrics.liquidGlassControlCornerRadius,
            style: .continuous,
        )
    }
}
