import AppKit
import SwiftUI

/// NSVisualEffectView wrapper for the translucent panel background.
/// Optionally tints the material with a translucent CALayer placed between the
/// material and the SwiftUI content — color is applied behind text, not over it,
/// so foreground content (including code block syntax colors) is unaffected.
struct VisualEffectView: NSViewRepresentable {
    var tint: NSColor?

    func makeNSView(context _: Context) -> TintableVisualEffectView {
        let view = TintableVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.tintColor = tint
        return view
    }

    func updateNSView(_ view: TintableVisualEffectView, context _: Context) {
        view.tintColor = tint
    }
}

final class TintableVisualEffectView: NSVisualEffectView {
    private let tintLayer: CALayer = {
        let l = CALayer()
        // Disable implicit animations on every property — the tint should not
        // slide, fade, or otherwise animate when the panel shows or resizes.
        l.actions = [
            "position": NSNull(), "bounds": NSNull(), "frame": NSNull(),
            "backgroundColor": NSNull(), "opacity": NSNull(), "hidden": NSNull(),
            "contents": NSNull(),
        ]
        return l
    }()

    var tintColor: NSColor? {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let tintColor {
                wantsLayer = true
                tintLayer.backgroundColor = tintColor.cgColor
                if tintLayer.superlayer == nil {
                    layer?.addSublayer(tintLayer)
                    tintLayer.frame = bounds
                }
            } else {
                tintLayer.removeFromSuperlayer()
            }
            CATransaction.commit()
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.frame = bounds
        CATransaction.commit()
    }
}
