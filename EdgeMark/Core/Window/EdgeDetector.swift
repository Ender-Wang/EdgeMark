import Cocoa

/// Detects when the mouse reaches the screen edge and triggers panel activation.
final class EdgeDetector {
    /// Called when the user dwells at the configured edge long enough. Passes the screen.
    var onEdgeActivated: ((NSScreen) -> Void)?

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var wasAtEdge = false
    private var activationTimer: Timer?
    private var isPaused = false

    /// How close to the edge (in points) the cursor must be to trigger activation.
    private let edgeThreshold: CGFloat = 2

    /// Height (in points) of corner exclusion zones to avoid macOS hot-corner conflicts.
    private let cornerExclusion: CGFloat = 50

    // MARK: - Public

    func startMonitoring() {
        guard globalMouseMonitor == nil else { return }
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
    }

    /// Resume detection after animation completes. Sets `wasAtEdge` based on
    /// current mouse position so the user must leave-and-return to re-trigger.
    func resumeDetection() {
        isPaused = false
        let mouseLocation = NSEvent.mouseLocation
        if let screen = screenForPoint(mouseLocation) {
            wasAtEdge = isAtEdge(mouseLocation: mouseLocation, visibleFrame: screen.visibleFrame)
        } else {
            wasAtEdge = false
        }
    }

    func stopMonitoring() {
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
        let mouseLocation = NSEvent.mouseLocation

        guard let screen = screenForPoint(mouseLocation) else { return }
        let visibleFrame = screen.visibleFrame

        let atEdge = isAtEdge(mouseLocation: mouseLocation, visibleFrame: visibleFrame)

        if atEdge, !wasAtEdge {
            // Just arrived at edge — start activation delay
            let delay = ShortcutSettings.shared.activationDelay
            if delay <= 0 {
                onEdgeActivated?(screen)
            } else {
                startActivation(delay: delay, screen: screen)
            }
        } else if !atEdge, wasAtEdge {
            cancelActivation()
        }

        wasAtEdge = atEdge
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

    private func isAtEdge(mouseLocation: NSPoint, visibleFrame: NSRect) -> Bool {
        // Right edge detection
        let atRightEdge = mouseLocation.x >= visibleFrame.maxX - edgeThreshold

        guard atRightEdge else { return false }

        // Corner exclusion: skip if cursor is within cornerExclusion of screen corners
        let distFromBottom = mouseLocation.y - visibleFrame.minY
        let distFromTop = visibleFrame.maxY - mouseLocation.y
        if distFromBottom < cornerExclusion || distFromTop < cornerExclusion {
            return false
        }

        return true
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
