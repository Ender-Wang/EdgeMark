import AppKit

/// Availability boundary for AppKit-owned floating surfaces that use Liquid Glass.
final class AppKitGlassSurface: NSView {
    enum Style {
        case regular
        case clear
    }

    init(
        frame: NSRect,
        contentView: NSView,
        style: Style = .regular,
        cornerRadius: CGFloat,
        tintColor: NSColor? = nil,
        isInteractive: Bool = false,
    ) {
        super.init(frame: frame)

        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true

        contentView.frame = bounds
        contentView.autoresizingMask = [.width, .height]

        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView(frame: bounds)
            glassView.autoresizingMask = [.width, .height]
            glassView.cornerRadius = cornerRadius
            glassView.style = style.glassStyle
            glassView.tintColor = tintColor
            glassView.contentView = contentView
            if #available(macOS 27.0, *) {
                glassView.effectIsInteractive = isInteractive
            }
            addSubview(glassView)
        } else {
            let materialView = NSVisualEffectView(frame: bounds)
            materialView.autoresizingMask = [.width, .height]
            materialView.material = .popover
            materialView.blendingMode = .behindWindow
            materialView.state = .active
            materialView.addSubview(contentView)
            addSubview(materialView)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(macOS 26.0, *)
private extension AppKitGlassSurface.Style {
    var glassStyle: NSGlassEffectView.Style {
        switch self {
        case .regular:
            .regular
        case .clear:
            .clear
        }
    }
}
