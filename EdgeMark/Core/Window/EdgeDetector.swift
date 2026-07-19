import Cocoa
import OSLog

/// Detects when the mouse reaches the screen edge and triggers panel activation.
final class EdgeDetector {
    /// Called when the user dwells at the configured edge long enough. Passes the screen.
    var onEdgeActivated: ((NSScreen) -> Void)?

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var lastHit: EdgeHit = .none
    private var activationTimer: Timer?
    private var isPaused = false
    private var isMenuOpen = false

    /// How close to the edge (in points) the cursor must be to trigger activation.
    private let edgeThreshold: CGFloat = 2

    /// Tolerance for treating two adjacent displays' edges as a shared seam
    /// (touching or near-touching) vs. a real gap. Two side-by-side displays
    /// placed with no gap share an exact edge; this absorbs sub-pixel rounding.
    private let seamTolerance: CGFloat = 2

    /// Height (in points) of corner exclusion zones to avoid macOS hot-corner conflicts.
    private let cornerExclusion: CGFloat = 50

    // MARK: - Public

    func startMonitoring() {
        guard globalMouseMonitor == nil else { return }
        Log.window.info("[EdgeDetector] started monitoring")
        // Global monitor: fires for mouse moves in OTHER apps' windows.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.handleMouseMove()
        }
        // Local monitor: fires for mouse moves in OUR app (covers the case
        // where EdgeMark is still the active app after the panel hides).
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMove()
            return event
        }
    }

    /// Pause detection during hide animation to prevent the race condition
    /// where a `mouseMoved` event during the animation re-sets `wasAtEdge`
    /// while `showPanel` is blocked by `isAnimating`.
    func pauseDetection() {
        isPaused = true
        cancelActivation()
        Log.window.debug("[EdgeDetector] paused")
    }

    /// Resume detection after animation completes. Sets `wasAtEdge` based on
    /// current mouse position so the user must leave-and-return to re-trigger.
    /// No-op if the menu bar menu is currently open.
    func resumeDetection() {
        guard !isMenuOpen else {
            Log.window.debug("[EdgeDetector] resume skipped — menu open")
            return
        }
        Log.window.debug("[EdgeDetector] resumed")
        isPaused = false
        let mouseLocation = NSEvent.mouseLocation
        if let screen = screenForPoint(mouseLocation) {
            lastHit = edgeHit(mouseLocation: mouseLocation, screen: screen)
        } else {
            lastHit = .none
        }
    }

    func menuWillOpen() {
        isMenuOpen = true
        pauseDetection()
    }

    func menuDidClose() {
        isMenuOpen = false
        resumeDetection()
    }

    func stopMonitoring() {
        Log.window.info("[EdgeDetector] stopped monitoring")
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
        cancelActivation()
    }

    // MARK: - Detection

    private func handleMouseMove() {
        guard !isPaused else { return }
        let t0 = CACurrentMediaTime()
        let mouseLocation = NSEvent.mouseLocation

        guard let screen = screenForPoint(mouseLocation) else { return }
        let hit = edgeHit(mouseLocation: mouseLocation, screen: screen)

        if hit == .exterior, lastHit != .exterior {
            // Just arrived at a trigger edge — start activation delay
            let delay = ShortcutSettings.shared.activationDelay
            if delay <= 0 {
                Log.window.debug("[EdgeDetector] edge hit — immediate activation")
                onEdgeActivated?(screen)
            } else {
                Log.window.debug("[EdgeDetector] edge hit — activation timer (\(delay)s)")
                startActivation(delay: delay, screen: screen)
            }
        } else if hit != .exterior, lastHit == .exterior {
            Log.window.debug("[EdgeDetector] left edge — cancelled")
            cancelActivation()
        }

        // Discriminating log: cursor reached the configured side's edge but
        // it's between two displays — not a desktop boundary, so no trigger.
        // Lets Console.app prove the gate fired (vs. the cursor just not
        // being near any edge). Fires once per arrival, not per mouseMove.
        if hit == .interior, lastHit != .interior {
            Log.window.debug("[EdgeDetector] interior edge ignored — not a desktop boundary")
        }

        lastHit = hit

        let elapsed = (CACurrentMediaTime() - t0) * 1000
        if elapsed > 2 {
            Log.window.warning("[EdgeDetector] handleMouseMove took \(String(format: "%.1f", elapsed))ms")
        }
    }

    /// Find the screen containing the point. Uses inclusive bounds (`<=` for
    /// maxX/maxY) so the cursor at the exact screen edge is still matched.
    private func screenForPoint(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            let f = screen.frame
            return point.x >= f.minX && point.x <= f.maxX
                && point.y >= f.minY && point.y <= f.maxY
        }
    }

    /// Three-state result of an edge check:
    /// - `none`: cursor not at the configured side's edge (or corner-excluded).
    /// - `interior`: at the side's edge, but it lies *between* two displays —
    ///   not a desktop boundary, so it must not trigger.
    /// - `exterior`: at a trigger edge on the global desktop boundary.
    enum EdgeHit: Equatable {
        case none
        case interior
        case exterior
    }

    /// Returns the edge state for the cursor. Interior edges (the seam between
    /// two side-by-side displays) never trigger — moving the mouse from one
    /// display to another shouldn't pop the panel on the display you're
    /// leaving. A display's edge is "interior" only when another display sits
    /// on the other side of it at an overlapping y-range; offset /
    /// vertically-stacked layouts are handled, since an edge with no neighbor
    /// beside it is exterior even if it isn't the global x-extreme.
    ///
    /// Single-display behavior is unchanged: the one screen has no neighbor,
    /// so its edge returns `.exterior` as before.
    private func edgeHit(mouseLocation: NSPoint, screen: NSScreen) -> EdgeHit {
        let settings = ShortcutSettings.shared
        guard settings.edgeActivationEnabled else { return .none }

        let visibleFrame = screen.visibleFrame

        // An edge is a *seam* (interior) if another display sits on the other
        // side of it with an overlapping y-range — i.e. the user crosses from
        // this screen onto that one. Otherwise it's a real desktop boundary
        // (exterior). This handles aligned side-by-side layouts *and* offset /
        // vertically-stacked arrangements where a screen's edge isn't the
        // global x-extreme but still has nothing beside it at its y-range.
        let atSideEdge: Bool
        let onExterior: Bool
        switch settings.edgeSide {
        case .right:
            atSideEdge = mouseLocation.x >= visibleFrame.maxX - edgeThreshold
            onExterior = !rightEdgeIsInterior(screen)
        case .left:
            atSideEdge = mouseLocation.x <= visibleFrame.minX + edgeThreshold
            onExterior = !leftEdgeIsInterior(screen)
        }

        guard atSideEdge else { return .none }
        guard onExterior else { return .interior }

        // Corner exclusion: skip if cursor is within cornerExclusion of screen corners
        if settings.excludeCorners {
            let distFromBottom = mouseLocation.y - visibleFrame.minY
            let distFromTop = visibleFrame.maxY - mouseLocation.y
            if distFromBottom < cornerExclusion || distFromTop < cornerExclusion {
                return .none
            }
        }

        return .exterior
    }

    /// True if another screen's left edge sits at this screen's right edge
    /// with an overlapping y-range — the seam you cross when moving the
    /// cursor from this display to the one on its right.
    private func rightEdgeIsInterior(_ screen: NSScreen) -> Bool {
        let s = screen.frame
        return NSScreen.screens.contains { other in
            guard other !== screen else { return false }
            let o = other.frame
            let leftEdgeAtOurRight = abs(o.minX - s.maxX) <= seamTolerance
            let yOverlap = min(o.maxY, s.maxY) - max(o.minY, s.minY) > seamTolerance
            return leftEdgeAtOurRight && yOverlap
        }
    }

    /// Symmetric to `rightEdgeIsInterior` for the left edge.
    private func leftEdgeIsInterior(_ screen: NSScreen) -> Bool {
        let s = screen.frame
        return NSScreen.screens.contains { other in
            guard other !== screen else { return false }
            let o = other.frame
            let rightEdgeAtOurLeft = abs(o.maxX - s.minX) <= seamTolerance
            let yOverlap = min(o.maxY, s.maxY) - max(o.minY, s.minY) > seamTolerance
            return rightEdgeAtOurLeft && yOverlap
        }
    }

    // MARK: - Activation Timer

    private func startActivation(delay: Double, screen: NSScreen) {
        cancelActivation()
        activationTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.onEdgeActivated?(screen)
        }
    }

    private func cancelActivation() {
        activationTimer?.invalidate()
        activationTimer = nil
    }

    deinit {
        stopMonitoring()
    }
}
