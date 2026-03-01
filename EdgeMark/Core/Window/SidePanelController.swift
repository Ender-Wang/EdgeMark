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
    private let cornerRadius: CGFloat = 10
    private(set) var isShown = false
    private var isAnimating = false
    private var animationGeneration = 0
    private var hideTimer: Timer?
    private var dummyWindow: NSWindow?
    private var trackingArea: NSTrackingArea?
    private var previousApp: NSRunningApplication?
    let edgeDetector: EdgeDetector
    let noteStore = NoteStore()
    let appSettings = AppSettings()

    // MARK: - Init

    init() {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelWidth: CGFloat = 400
        let side = ShortcutSettings.shared.edgeSide

        // Start off-screen on the configured edge
        let startX: CGFloat = switch side {
        case .right: visibleFrame.maxX
        case .left: visibleFrame.minX - panelWidth
        }

        let window = KeyableWindow(
            contentRect: NSRect(
                x: startX,
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
        let hostingView = NSHostingView(rootView: ContentView().environment(noteStore).environment(appSettings))
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: visibleFrame.height)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 10
        hostingView.layer?.maskedCorners = Self.maskedCorners(for: side)
        hostingView.layer?.masksToBounds = true
        window.contentView = hostingView

        edgeDetector = EdgeDetector()

        super.init(window: window)

        // Order the window off-screen immediately so it joins all Spaces.
        // We never orderOut — the window stays ordered (off-screen when hidden)
        // to maintain its .canJoinAllSpaces membership across desktop switches.
        window.orderBack(nil)

        setupDummyWindow()
        setupTrackingArea()

        edgeDetector.onEdgeActivated = { [weak self] screen in
            self?.showPanel(on: screen)
        }
        edgeDetector.startMonitoring()

        // Click-outside dismissal
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, isShown, !self.isMouseInPanel(),
                  ShortcutSettings.shared.hideOnClickOutside else { return }
            hidePanel()
        }

        // Escape key dismissal
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.isShown == true {
                // If a SwiftUI TextField is focused (field editor is first responder),
                // let the event propagate so SwiftUI can handle it (e.g. dismiss search).
                if let fr = self?.window?.firstResponder as? NSTextView, fr.isFieldEditor {
                    return event
                }
                self?.hidePanel()
            }
            return event
        }

        // Clear previousApp on desktop switch so we don't yank the user back
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSpaceChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
        )

        // Listen for settings changes (e.g. edge side) to reconfigure the panel
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .shortcutSettingsChanged,
            object: nil,
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Settings Change

    @objc private func handleSettingsChanged() {
        guard let window, let hostingView = window.contentView else { return }

        // Update corner radius for new edge side
        let side = ShortcutSettings.shared.edgeSide
        hostingView.layer?.maskedCorners = Self.maskedCorners(for: side)

        // If panel is visible, hide it — user re-triggers to see it on the new edge
        if isShown {
            hidePanel()
        } else {
            // Reposition off-screen on the new edge
            let targetScreen = window.screen ?? NSScreen.main ?? NSScreen.screens.first!
            let visibleFrame = targetScreen.visibleFrame
            let (_, hidden) = panelFrames(visibleFrame: visibleFrame, side: side)
            window.setFrame(hidden, display: false)
        }
    }

    // MARK: - Space Change

    @objc private func handleSpaceChange() {
        // Clear previousApp so hidePanel() doesn't activate an app on a
        // different Space and yank the user back.
        previousApp = nil

        // If the panel is shown and the mouse is outside, restart the auto-hide
        // timer with a short delay so the animation plays after the Space
        // transition settles (animations don't render mid-transition).
        guard isShown else { return }
        cancelHideTimer()
        if !isMouseInPanel() {
            let delay = max(ShortcutSettings.shared.hideDelay, 0.5)
            startHideTimer(delay: delay)
        }
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
        guard isShown, !isAnimating, !isEditorFocused,
              ShortcutSettings.shared.autoHideOnMouseExit else { return }
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
        guard let window, !isShown else { return }
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = targetScreen.visibleFrame
        let side = ShortcutSettings.shared.edgeSide

        isShown = true
        let gen = animationGeneration &+ 1
        animationGeneration = gen

        let (shownFrame, startFrame) = panelFrames(visibleFrame: visibleFrame, side: side)

        // Save the frontmost app so we can restore focus when hiding
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
        }

        window.alphaValue = 1

        if isAnimating {
            // Interrupt hide animation — snap to shown position
            isAnimating = false
            window.setFrame(shownFrame, display: true)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Normal animated show
            isAnimating = true
            // Pre-render at start position so SwiftUI layout is done before animation
            window.setFrame(startFrame, display: true)
            window.makeKeyAndOrderFront(nil)

            // Slide in without forcing redisplay on each frame (content doesn't change, only position)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(shownFrame, display: false)
            } completionHandler: { [weak self] in
                guard let self, animationGeneration == gen else { return }
                isAnimating = false
            }

            // Activate after animation is submitted to Core Animation — avoids blocking the slide
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func hidePanel() {
        guard let window, isShown else { return }
        noteStore.saveDirtyNotes()
        isShown = false
        let gen = animationGeneration &+ 1
        animationGeneration = gen
        cancelHideTimer()
        edgeDetector.pauseDetection()

        let targetScreen = window.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = targetScreen.visibleFrame
        let side = ShortcutSettings.shared.edgeSide
        let (_, hiddenFrame) = panelFrames(visibleFrame: visibleFrame, side: side)

        if isAnimating {
            // Interrupt show animation — snap to hidden position
            isAnimating = false
            window.setFrame(hiddenFrame, display: false)
            window.alphaValue = 0
            restorePreviousApp()
            edgeDetector.resumeDetection()
        } else {
            isAnimating = true

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().setFrame(hiddenFrame, display: false)
            } completionHandler: { [weak self] in
                guard let self, animationGeneration == gen else { return }
                window.alphaValue = 0
                isAnimating = false
                restorePreviousApp()
                edgeDetector.resumeDetection()
            }
        }
    }

    func togglePanel() {
        if isShown {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Frame Calculation

    /// Returns (shown, hidden) frames for the given edge side.
    private func panelFrames(visibleFrame: NSRect, side: EdgeSide) -> (shown: NSRect, hidden: NSRect) {
        let shown: NSRect
        let hidden: NSRect
        switch side {
        case .right:
            shown = NSRect(x: visibleFrame.maxX - panelWidth, y: visibleFrame.minY,
                           width: panelWidth, height: visibleFrame.height)
            hidden = NSRect(x: visibleFrame.maxX, y: visibleFrame.minY,
                            width: panelWidth, height: visibleFrame.height)
        case .left:
            shown = NSRect(x: visibleFrame.minX, y: visibleFrame.minY,
                           width: panelWidth, height: visibleFrame.height)
            hidden = NSRect(x: visibleFrame.minX - panelWidth, y: visibleFrame.minY,
                            width: panelWidth, height: visibleFrame.height)
        }
        return (shown, hidden)
    }

    /// Corner mask for the given edge side.
    private static func maskedCorners(for side: EdgeSide) -> CACornerMask {
        switch side {
        case .right:
            // Right edge → round left corners
            [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        case .left:
            // Left edge → round right corners
            [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }
    }

    // MARK: - Helpers

    /// Reactivate the app that was frontmost before the panel appeared,
    /// so its mouse events go through the global monitor again.
    /// Skips restoration if another EdgeMark window (e.g. Settings, Update) is key.
    private func restorePreviousApp() {
        let hasOtherKeyWindow = NSApp.windows.contains { $0 !== window && $0.isKeyWindow }
        if !hasOtherKeyWindow {
            previousApp?.activate()
        }
        previousApp = nil
    }

    private func isMouseInPanel() -> Bool {
        guard let window else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    private func startHideTimer(delay: Double) {
        cancelHideTimer()
        hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, isShown, !isMouseInPanel() else { return }
            hidePanel()
        }
    }

    private func cancelHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    /// Whether an NSTextView in the panel is the first responder (user is editing).
    private var isEditorFocused: Bool {
        window?.firstResponder is NSTextView
    }
}
