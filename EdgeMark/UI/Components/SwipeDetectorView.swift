import AppKit
import SwiftUI

/// Transparent overlay that detects two-finger trackpad right-swipe (back navigation)
/// via NSEvent scroll monitoring. Only fires when the cursor is inside this view's bounds.
/// Mouse clicks pass through (hitTest returns nil).
struct SwipeDetectorView: NSViewRepresentable {
    let onSwipeBack: () -> Void

    func makeNSView(context _: Context) -> SwipeDetectorNSView {
        let view = SwipeDetectorNSView()
        view.onSwipeBack = onSwipeBack
        return view
    }

    func updateNSView(_ nsView: SwipeDetectorNSView, context _: Context) {
        nsView.onSwipeBack = onSwipeBack
    }
}

final class SwipeDetectorNSView: NSView {
    var onSwipeBack: (() -> Void)?

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
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }

    private func stopMonitoring() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard window != nil else { return }

        // Only respond to events where the cursor is inside this view (the header card)
        let locationInSelf = convert(event.locationInWindow, from: nil)
        guard bounds.contains(locationInSelf) else { return }

        let settings = ShortcutSettings.shared
        guard let onSwipeBack, settings.swipeToNavigateEnabled else { return }

        if event.phase == .began {
            accumulatedDeltaX = 0
        }

        accumulatedDeltaX += event.scrollingDeltaX

        if event.phase == .ended {
            let threshold = CGFloat(80 - 65 * settings.swipeGestureSensitivity)
            // Positive deltaX = right swipe (natural scrolling, macOS default)
            if accumulatedDeltaX > threshold {
                DispatchQueue.main.async { onSwipeBack() }
            }
            accumulatedDeltaX = 0
        }
    }

    /// Transparent to mouse clicks — let buttons underneath handle them
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}
