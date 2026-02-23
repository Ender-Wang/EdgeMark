import Cocoa
import SwiftUI

// MARK: - KeyableWindow

/// Custom NSWindow subclass that can become key and main (required for borderless windows).
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

// MARK: - SidePanelController

final class SidePanelController: NSWindowController {
    private let panelWidth: CGFloat = 400
    private let cornerRadius: CGFloat = 12
    private(set) var isShown = false
    private var isAnimating = false
    private var hideTimer: Timer?
    private var dummyWindow: NSWindow?
    private var trackingArea: NSTrackingArea?
    let edgeDetector: EdgeDetector

    // MARK: - Init

    init() {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelWidth: CGFloat = 400

        // Start off-screen to the right
        let window = KeyableWindow(
            contentRect: NSRect(
                x: visibleFrame.maxX,
                y: visibleFrame.minY,
                width: panelWidth,
                height: visibleFrame.height,
            ),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = false

        // Host SwiftUI content
        let hostingView = NSHostingView(rootView: ContentView())
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: visibleFrame.height)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 12
        // Right edge panel → round left corners only
        hostingView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        hostingView.layer?.masksToBounds = true
        window.contentView = hostingView

        edgeDetector = EdgeDetector()

        super.init(window: window)

        setupDummyWindow()
        setupTrackingArea()

        edgeDetector.onEdgeActivated = { [weak self] screen in
            self?.showPanel(on: screen)
        }
        edgeDetector.startMonitoring()

        // Click-outside dismissal
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, isShown, !self.isMouseInPanel() else { return }
            hidePanel()
        }

        // Escape key dismissal
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.isShown == true {
                self?.hidePanel()
            }
            return event
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Dummy Window

    /// A 1×1 invisible window used as a focus chain anchor so the panel can resign
    /// key status without the system sending focus to a random window.
    private func setupDummyWindow() {
        let dummy = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )
        dummy.isOpaque = false
        dummy.backgroundColor = .clear
        dummy.alphaValue = 0
        dummy.ignoresMouseEvents = true
        dummy.level = .floating
        dummy.collectionBehavior = [.stationary, .ignoresCycle]
        dummy.orderBack(nil)
        dummyWindow = dummy
    }

    // MARK: - Tracking Area (auto-hide)

    private func setupTrackingArea() {
        guard let contentView = window?.contentView else { return }
        trackingArea = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil,
        )
        contentView.addTrackingArea(trackingArea!)
    }

    override func mouseExited(with _: NSEvent) {
        guard isShown else { return }
        let delay = ShortcutSettings.shared.hideDelay
        if delay == 0 {
            hidePanel()
        } else {
            startHideTimer(delay: delay)
        }
    }

    override func mouseEntered(with _: NSEvent) {
        cancelHideTimer()
    }

    // MARK: - Show / Hide

    func showPanel(on screen: NSScreen? = nil) {
        guard let window, !isShown, !isAnimating else { return }
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = targetScreen.visibleFrame

        isShown = true
        isAnimating = true

        // Position off-screen at the right edge
        window.setFrame(
            NSRect(x: visibleFrame.maxX, y: visibleFrame.minY, width: panelWidth, height: visibleFrame.height),
            display: false,
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(
                NSRect(x: visibleFrame.maxX - panelWidth, y: visibleFrame.minY, width: panelWidth, height: visibleFrame.height),
                display: true,
            )
        } completionHandler: { [weak self] in
            self?.isAnimating = false
        }
    }

    func hidePanel() {
        guard let window, isShown, !isAnimating else { return }
        isShown = false
        isAnimating = true
        cancelHideTimer()
        edgeDetector.resetEdgeState()

        let frame = window.frame
        let offScreenX = frame.maxX // slide right to hide

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(
                NSRect(x: offScreenX, y: frame.minY, width: panelWidth, height: frame.height),
                display: true,
            )
        } completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.isAnimating = false
        }
    }

    func togglePanel() {
        if isShown {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Helpers

    private func isMouseInPanel() -> Bool {
        guard let window else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    private func startHideTimer(delay: Double) {
        cancelHideTimer()
        hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, isShown, !self.isMouseInPanel() else { return }
            hidePanel()
        }
    }

    private func cancelHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }
}
