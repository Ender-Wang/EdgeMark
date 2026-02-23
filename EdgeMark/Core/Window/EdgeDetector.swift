import Cocoa

/// Detects when the mouse reaches the screen edge and triggers panel activation.
final class EdgeDetector {
    /// Called when the user dwells at the configured edge long enough. Passes the screen.
    var onEdgeActivated: ((NSScreen) -> Void)?

    private var mouseMoveMonitor: Any?
    private var wasAtEdge = false
    private var activationTimer: Timer?

    /// How close to the edge (in points) the cursor must be to trigger activation.
    private let edgeThreshold: CGFloat = 2

    /// Height (in points) of corner exclusion zones to avoid macOS hot-corner conflicts.
    private let cornerExclusion: CGFloat = 50

    // MARK: - Public

    func startMonitoring() {
        guard mouseMoveMonitor == nil else { return }
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.handleMouseMove()
        }
    }

    /// Reset edge state so the next edge arrival triggers activation.
    /// Call this when the panel hides — global monitor doesn't see mouse
    /// movements inside our own window, so `wasAtEdge` can get stuck `true`.
    func resetEdgeState() {
        wasAtEdge = false
        cancelActivation()
    }

    func stopMonitoring() {
        if let monitor = mouseMoveMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMoveMonitor = nil
        }
        cancelActivation()
    }

    // MARK: - Detection

    private func handleMouseMove() {
        let mouseLocation = NSEvent.mouseLocation

        // Find the screen the cursor is on
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else { return }
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
