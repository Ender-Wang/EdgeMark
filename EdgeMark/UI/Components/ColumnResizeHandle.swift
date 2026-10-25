import AppKit
import SwiftUI

/// An AppKit-backed split handle so Column mode tracks the pointer directly
/// and presents the native horizontal-resize cursor over a generous hit area.
struct ColumnResizeHandle: NSViewRepresentable {
    let currentWidth: CGFloat
    let minimumWidth: CGFloat
    let maximumWidth: CGFloat
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat) -> Void

    func makeNSView(context _: Context) -> ColumnResizeHandleView {
        ColumnResizeHandleView()
    }

    func updateNSView(_ view: ColumnResizeHandleView, context _: Context) {
        view.currentWidth = currentWidth
        view.minimumWidth = minimumWidth
        view.maximumWidth = maximumWidth
        view.onChanged = onChanged
        view.onEnded = onEnded
    }
}

final class ColumnResizeHandleView: NSView {
    var currentWidth: CGFloat = PanelLayoutMetrics.defaultNavigationWidth
    var minimumWidth: CGFloat = PanelLayoutMetrics.minimumNavigationWidth
    var maximumWidth: CGFloat = PanelLayoutMetrics.columnBreakpoint / 2
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: ((CGFloat) -> Void)?

    private var dragStartX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.splitter)
        setAccessibilityOrientation(.vertical)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with _: NSEvent) {
        dragStartX = NSEvent.mouseLocation.x
        dragStartWidth = currentWidth
    }

    override func mouseDragged(with _: NSEvent) {
        let delta = NSEvent.mouseLocation.x - dragStartX
        currentWidth = clamped(dragStartWidth + delta)
        onChanged?(currentWidth)
    }

    override func mouseUp(with _: NSEvent) {
        currentWidth = clamped(currentWidth)
        onEnded?(currentWidth)
        NSCursor.arrow.set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil,
        ))
    }

    override func cursorUpdate(with _: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    private func clamped(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumWidth), maximumWidth)
    }
}
