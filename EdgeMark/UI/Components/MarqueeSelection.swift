import Cocoa
import SwiftUI

// MARK: - Row Frame Reporting

/// A SwiftUI `PreferenceKey` that aggregates each row's frame in a shared
/// coordinate space, keyed by `NoteStore.SelectableID`. The marquee overlay
/// reads these frames to compute drag-rect intersections and to know which
/// areas are "row" vs. "empty" for hit-testing.
struct RowFramesKey: PreferenceKey {
    static let defaultValue: [NoteStore.SelectableID: CGRect] = [:]

    static func reduce(
        value: inout [NoteStore.SelectableID: CGRect],
        nextValue: () -> [NoteStore.SelectableID: CGRect],
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Named coordinate space that anchors row-frame reporting and the marquee
/// overlay to the same origin.
enum MarqueeCoordinateSpace {
    static let name = "EdgeMark.Marquee"
}

extension View {
    /// Report this row's frame so the enclosing `marqueeSelection` overlay can
    /// hit-test against it. Attach to every selectable row inside a marquee
    /// container.
    func reportRowFrame(_ id: NoteStore.SelectableID) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(
                key: RowFramesKey.self,
                value: [id: geo.frame(in: .named(MarqueeCoordinateSpace.name))],
            )
        })
    }
}

// MARK: - Container Modifier

/// Adds Finder-style marquee (drag-rectangle) selection to a list container.
///
/// - `baseline`: snapshot of the existing selection captured at `mouseDown`.
///   Used together with `⇧` (union) and `⌘` (symmetric difference) modifiers.
/// - `apply`: receives the resolved selection set on each drag tick.
/// - `onClick`: empty-area click without drag (typically `clearSelection`).
struct MarqueeSelectionModifier: ViewModifier {
    let baseline: () -> Set<NoteStore.SelectableID>
    let apply: (Set<NoteStore.SelectableID>) -> Void
    let onClick: () -> Void

    @State private var rowFrames: [NoteStore.SelectableID: CGRect] = [:]

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: MarqueeCoordinateSpace.name)
            .onPreferenceChange(RowFramesKey.self) { rowFrames = $0 }
            .background {
                MarqueeOverlay(
                    rowFrames: rowFrames,
                    baseline: baseline,
                    apply: apply,
                    onClick: onClick,
                )
            }
    }
}

extension View {
    /// Wraps the view with a marquee-selection overlay. `baseline` is read at
    /// `mouseDown`; `apply` receives the resolved selection on each drag tick.
    func marqueeSelection(
        baseline: @escaping () -> Set<NoteStore.SelectableID>,
        apply: @escaping (Set<NoteStore.SelectableID>) -> Void,
        onClick: @escaping () -> Void,
    ) -> some View {
        modifier(MarqueeSelectionModifier(baseline: baseline, apply: apply, onClick: onClick))
    }
}

// MARK: - AppKit Overlay

private struct MarqueeOverlay: NSViewRepresentable {
    let rowFrames: [NoteStore.SelectableID: CGRect]
    let baseline: () -> Set<NoteStore.SelectableID>
    let apply: (Set<NoteStore.SelectableID>) -> Void
    let onClick: () -> Void

    func makeNSView(context _: Context) -> MarqueeView {
        let view = MarqueeView()
        view.rowFrames = rowFrames
        view.getBaseline = baseline
        view.applySelection = apply
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: MarqueeView, context _: Context) {
        nsView.rowFrames = rowFrames
        nsView.getBaseline = baseline
        nsView.applySelection = apply
        nsView.onClick = onClick
    }
}

/// Transparent NSView placed behind the row stack. Claims `mouseDown` only
/// when the click lands in empty space (i.e. not over any reported row),
/// then tracks dragging to draw a translucent rectangle and update selection.
final class MarqueeView: NSView {
    var rowFrames: [NoteStore.SelectableID: CGRect] = [:]
    var getBaseline: (() -> Set<NoteStore.SelectableID>)?
    var applySelection: ((Set<NoteStore.SelectableID>) -> Void)?
    var onClick: (() -> Void)?

    private var dragOrigin: NSPoint?
    private var didDrag = false
    private let dragThreshold: CGFloat = 4

    private var baselineSelection: Set<NoteStore.SelectableID> = []
    private var lastDragEvent: NSEvent?
    private var autoScrollTimer: Timer?

    private let rectLayer = CAShapeLayer()

    /// Use Y-down coordinates so our local rect aligns with SwiftUI's named
    /// coordinate space (which is also top-left origin).
    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configureRectLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        configureRectLayer()
    }

    private func configureRectLayer() {
        rectLayer.fillColor = NSColor.controlAccentColor
            .withAlphaComponent(0.18).cgColor
        rectLayer.strokeColor = NSColor.controlAccentColor.cgColor
        rectLayer.lineWidth = 1
        rectLayer.isHidden = true
        layer?.addSublayer(rectLayer)
    }

    // MARK: Hit-testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only claim left mouse-down events; let everything else (right-clicks,
        // scrolls, hovers) pass through to SwiftUI.
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown else {
            return nil
        }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }

        // If the click landed on a row, let the row's `.rowClick` overlay handle it.
        for frame in rowFrames.values where frame.contains(local) {
            return nil
        }
        return self
    }

    // MARK: Mouse events

    override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil)
        didDrag = false
        baselineSelection = getBaseline?() ?? []
        lastDragEvent = event

        // Periodic ticks let auto-scroll continue while the cursor is held still
        // past the viewport edge — `mouseDragged` only fires on movement.
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.autoScrollTick()
        }
        if let timer = autoScrollTimer {
            RunLoop.current.add(timer, forMode: .eventTracking)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        lastDragEvent = event
        autoscroll(with: event)
        updateMarquee(with: event)
    }

    override func mouseUp(with _: NSEvent) {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        lastDragEvent = nil

        defer {
            dragOrigin = nil
            didDrag = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            rectLayer.isHidden = true
            rectLayer.path = nil
            CATransaction.commit()
        }
        if !didDrag {
            onClick?()
        }
    }

    // MARK: Marquee math

    private func autoScrollTick() {
        guard let event = lastDragEvent else { return }
        if autoscroll(with: event) {
            // The view scrolled — recompute marquee against the new geometry.
            updateMarquee(with: event)
        }
    }

    private func updateMarquee(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let current = convert(event.locationInWindow, from: nil)
        let dx = current.x - origin.x
        let dy = current.y - origin.y

        // Below threshold: still treat as pending click, don't draw or select yet.
        if !didDrag, hypot(dx, dy) < dragThreshold {
            return
        }
        didDrag = true

        let rect = NSRect(
            x: min(origin.x, current.x),
            y: min(origin.y, current.y),
            width: abs(dx),
            height: abs(dy),
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rectLayer.path = CGPath(rect: rect, transform: nil)
        rectLayer.isHidden = false
        CATransaction.commit()

        let hits: Set<NoteStore.SelectableID> = Set(rowFrames.compactMap { id, frame in
            frame.intersects(rect) ? id : nil
        })

        // Resolve final selection per Finder-style modifier rules.
        let mods = event.modifierFlags
        let resolved: Set<NoteStore.SelectableID> = if mods.contains(.command) {
            baselineSelection.symmetricDifference(hits)
        } else if mods.contains(.shift) {
            baselineSelection.union(hits)
        } else {
            hits
        }
        applySelection?(resolved)
    }
}
