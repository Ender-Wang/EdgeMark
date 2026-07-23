import AppKit
import OSLog
import SwiftUI

/// Transparent overlay that detects two-finger trackpad horizontal swipes
/// via NSEvent scroll monitoring. Only fires when the scroll belongs to this
/// view's window and the cursor is inside its bounds. Mouse clicks pass through.
struct SwipeDetectorView: NSViewRepresentable {
    var onSwipeBack: (() -> Void)?
    var onSwipeForward: (() -> Void)?

    func makeNSView(context _: Context) -> SwipeDetectorNSView {
        let view = SwipeDetectorNSView()
        view.onSwipeBack = onSwipeBack
        view.onSwipeForward = onSwipeForward
        return view
    }

    func updateNSView(_ nsView: SwipeDetectorNSView, context _: Context) {
        nsView.onSwipeBack = onSwipeBack
        nsView.onSwipeForward = onSwipeForward
    }
}

final class SwipeDetectorNSView: NSView {
    var onSwipeBack: (() -> Void)?
    var onSwipeForward: (() -> Void)?

    private var monitor: Any?
    private var accumulatedDeltaX: CGFloat = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        Log.navigation.debug("[SwipeDetector] monitoring started")
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }

    private func stopMonitoring() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
            Log.navigation.debug("[SwipeDetector] monitoring stopped")
        }
    }

    private func handleScroll(_ event: NSEvent) {
        // A local scrollWheel monitor fires for every app window, not just this one.
        // Ignore scrolls that belong to a different window (e.g. the Settings panel) —
        // otherwise a horizontal scroll in Settings can navigate the open note when the
        // Settings window overlaps the panel (event.locationInWindow is in the other
        // window's coordinate space, so the bounds check below is meaningless for it).
        guard let viewWindow = window, event.window === viewWindow else { return }

        // Only respond to events where the cursor is inside this view (the header card)
        let locationInSelf = convert(event.locationInWindow, from: nil)
        guard bounds.contains(locationInSelf) else { return }

        let settings = ShortcutSettings.shared
        guard settings.swipeToNavigateEnabled,
              onSwipeBack != nil || onSwipeForward != nil
        else { return }

        if event.phase == .began {
            accumulatedDeltaX = 0
        }

        accumulatedDeltaX += event.scrollingDeltaX

        if event.phase == .ended {
            let threshold = CGFloat(80 - 65 * settings.swipeGestureSensitivity)
            let delta = accumulatedDeltaX
            // Positive deltaX = right swipe (natural scrolling, macOS default)
            if delta > threshold, let onSwipeBack {
                Log.navigation.debug("[SwipeDetector] swipe-back fired (delta: \(delta, privacy: .public), threshold: \(threshold, privacy: .public))")
                DispatchQueue.main.async { onSwipeBack() }
            }
            // Negative deltaX = left swipe = forward
            if delta < -threshold, let onSwipeForward {
                Log.navigation.debug("[SwipeDetector] swipe-forward fired (delta: \(delta, privacy: .public), threshold: \(threshold, privacy: .public))")
                DispatchQueue.main.async { onSwipeForward() }
            }
            accumulatedDeltaX = 0
        }
    }

    /// Transparent to mouse clicks — let buttons underneath handle them
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}
