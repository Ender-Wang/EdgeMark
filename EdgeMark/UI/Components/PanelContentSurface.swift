import SwiftUI

/// The stable content layer behind a page section such as its header, list, or editor.
/// Liquid Glass is reserved for controls; content continues to use standard
/// material so text and selection states remain calm and legible.
struct PanelContentSurface: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    if let tint = appSettings.panelTint.color {
                        Color(nsColor: tint)
                    }
                }
            } else {
                VisualEffectView(
                    tint: appSettings.panelTint.color,
                    material: appSettings.panelStyle.material,
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
