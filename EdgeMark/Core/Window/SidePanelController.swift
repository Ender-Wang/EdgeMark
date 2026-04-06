import Cocoa
import OSLog
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
    private let cornerRadius: CGFloat = 10
    private(set) var isShown = false
    private var isAnimating = false
    private var animationGeneration = 0
    private var hideTimer: Timer?
    private var dummyWindow: NSWindow?
    private var trackingArea: NSTrackingArea?
    private var previousApp: NSRunningApplication?
    /// Retained reference to the SwiftUI hosting view for layer updates.
    private var contentHostingView: NSView?
    /// Retained reference to the drag-to-resize handle for repositioning.
    private var resizeHandleView: ResizeHandleView?
    let edgeDetector: EdgeDetector
    let noteStore = NoteStore()
    let appSettings = AppSettings()

    // MARK: - Init

    init() {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelWidth = ShortcutSettings.shared.panelWidth
        let side = ShortcutSettings.shared.edgeSide

        // Park the window far off-screen so it can't overlap any monitor.
        // Using a large negative coordinate is guaranteed to miss all monitor arrangements.
        let startX: CGFloat = -panelWidth - 1000

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
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = false

        // Container view — sits between the window and the SwiftUI hosting view so we can
        // layer the resize handle on top without interfering with SwiftUI layout.
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: visibleFrame.height))

        // Host SwiftUI content — fills the container
        let hostingView = NSHostingView(
            rootView: ContentView()
                .environment(noteStore)
                .environment(appSettings)
                .environment(L10n.shared),
        )
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 10
        hostingView.layer?.maskedCorners = Self.maskedCorners(for: side)
        hostingView.layer?.masksToBounds = true
        containerView.addSubview(hostingView)

        // Resize handle — thin strip on the inner edge
        let handle = ResizeHandleView()
        handle.side = side
        handle.frame = Self.resizeHandleFrame(for: side, containerWidth: panelWidth, height: visibleFrame.height)
        handle.autoresizingMask = Self.resizeHandleAutoresizing(for: side)
        containerView.addSubview(handle)

        window.contentView = containerView

        edgeDetector = EdgeDetector()

        super.init(window: window)

        contentHostingView = hostingView
        resizeHandleView = handle

        handle.onDrag = { [weak self] newWidth in self?.panelDidResize(to: newWidth) }
        handle.onDragEnded = { [weak self] finalWidth in self?.panelResizeEnded(width: finalWidth) }

        // Order the window off-screen immediately so it joins all Spaces.
        // We never orderOut — the window stays ordered (off-screen when hidden)
        // to maintain its .canJoinAllSpaces membership across desktop switches.
        window.orderBack(nil)
        // Start invisible and non-interactive. The parking position for a right-edge panel
        // on screen A lands inside an adjacent screen B's coordinate space — both alpha=0
        // (no visual ghost) and ignoresMouseEvents=true (no click swallowing) are needed.
        window.alphaValue = 0
        window.ignoresMouseEvents = true

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

        // Update previousApp when user switches apps while panel is shown
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
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
        guard let window, let containerView = window.contentView else { return }

        // Update corner radius for new edge side
        let side = ShortcutSettings.shared.edgeSide
        Log.window.info("[SidePanelController] settings changed — edge: \(side.rawValue, privacy: .public)")
        contentHostingView?.layer?.maskedCorners = Self.maskedCorners(for: side)

        // Reposition resize handle for new edge side
        let panelWidth = ShortcutSettings.shared.panelWidth
        resizeHandleView?.side = side
        resizeHandleView?.autoresizingMask = Self.resizeHandleAutoresizing(for: side)
        resizeHandleView?.frame = Self.resizeHandleFrame(for: side, containerWidth: panelWidth, height: containerView.bounds.height)

        // If panel is visible, hide it — user re-triggers to see it on the new edge
        if isShown {
            hidePanel()
        } else {
            // Reposition to safe parked location (edge may have changed so old position is stale)
            window.setFrame(parkedFrame(panelWidth: panelWidth), display: false)
        }
    }

    // MARK: - Space Change

    @objc private func handleSpaceChange() {
        Log.window.debug("[SidePanelController] space changed")
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

    // MARK: - App Activation

    @objc private func handleAppActivation(_ notification: Notification) {
        guard isShown else { return }
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        else { return }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }

        let name = app.localizedName ?? "unknown"
        Log.window.debug(
            "[SidePanelController] app activated while panel shown — updating previousApp to \(name, privacy: .public)",
        )
        previousApp = app
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
            Log.window.debug("[SidePanelController] mouseExited — hide timer (\(delay)s)")
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
        Log.window.info("[SidePanelController] showPanel (\(side.rawValue, privacy: .public) edge)")

        // Check for external file changes every time the panel becomes visible
        noteStore.checkForExternalChanges()

        isShown = true
        let gen = animationGeneration &+ 1
        animationGeneration = gen

        let (shownFrame, _) = panelFrames(visibleFrame: visibleFrame, side: side)

        // Save the frontmost app so we can restore focus when hiding
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
        }

        if isAnimating {
            // Interrupt hide animation — snap to shown position instantly
            Log.window.debug("[SidePanelController] showPanel interrupted hide animation")
            isAnimating = false
            window.setFrame(shownFrame, display: true)
            window.alphaValue = 1
            window.ignoresMouseEvents = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            isAnimating = true
            window.ignoresMouseEvents = false
            window.makeKeyAndOrderFront(nil)

            if ShortcutSettings.shared.animationStyle == .slide {
                // Slide: teleport to the off-screen start position, then animate the frame inward.
                // Note: on multi-monitor setups the start position may overlap the adjacent display,
                // causing a brief ghost during the 0.2s travel. Use Fade in Settings to avoid this.
                let (_, startFrame) = panelFrames(visibleFrame: visibleFrame, side: side)
                window.setFrame(startFrame, display: true)
                window.alphaValue = 1

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().setFrame(shownFrame, display: false)
                } completionHandler: { [weak self] in
                    guard let self, animationGeneration == gen else { return }
                    isAnimating = false
                }
            } else {
                // Fade: position at the final frame while invisible, then animate alpha 0 → 1.
                // The window never moves off the triggering screen — no adjacent monitor bleed.
                window.setFrame(shownFrame, display: true)
                window.alphaValue = 0

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = 1
                } completionHandler: { [weak self] in
                    guard let self, animationGeneration == gen else { return }
                    isAnimating = false
                }
            }

            // Activate after animation is submitted to Core Animation
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func hidePanel() {
        guard let window, isShown else { return }
        Log.window.info("[SidePanelController] hidePanel")
        noteStore.saveDirtyNotes()
        isShown = false
        let gen = animationGeneration &+ 1
        animationGeneration = gen
        cancelHideTimer()
        edgeDetector.pauseDetection()

        let panelWidth = window.frame.width
        let targetScreen = window.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = targetScreen.visibleFrame
        let side = ShortcutSettings.shared.edgeSide
        let (_, hiddenFrame) = panelFrames(visibleFrame: visibleFrame, side: side)

        if isAnimating {
            // Interrupt show animation — snap to parked position instantly
            Log.window.debug("[SidePanelController] hidePanel interrupted show animation")
            isAnimating = false
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.setFrame(parkedFrame(panelWidth: panelWidth), display: false)
            restorePreviousApp()
            edgeDetector.resumeDetection()
        } else {
            isAnimating = true
            window.ignoresMouseEvents = true

            if ShortcutSettings.shared.animationStyle == .slide {
                // Slide out, then park far off-screen so the invisible window can't block clicks.
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    window.animator().setFrame(hiddenFrame, display: false)
                } completionHandler: { [weak self] in
                    guard let self, animationGeneration == gen else { return }
                    window.alphaValue = 0
                    window.setFrame(parkedFrame(panelWidth: panelWidth), display: false)
                    isAnimating = false
                    restorePreviousApp()
                    edgeDetector.resumeDetection()
                }
            } else {
                // Fade out in place, then park. Window never moves off the current screen.
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    window.animator().alphaValue = 0
                } completionHandler: { [weak self] in
                    guard let self, animationGeneration == gen else { return }
                    window.setFrame(parkedFrame(panelWidth: panelWidth), display: false)
                    isAnimating = false
                    restorePreviousApp()
                    edgeDetector.resumeDetection()
                }
            }
        }
    }

    func togglePanel() {
        let state = isShown ? "shown" : "hidden"
        Log.window.debug("[SidePanelController] togglePanel (currently \(state, privacy: .public))")
        if isShown {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Resize

    private func panelDidResize(to newWidth: CGFloat) {
        guard let window else { return }
        let side = ShortcutSettings.shared.edgeSide
        let targetScreen = window.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let maxWidth = targetScreen.visibleFrame.width - 100
        let clampedWidth = min(max(newWidth, ResizeHandleView.minWidth), maxWidth)

        var frame = window.frame
        if side == .right {
            // Right screen edge is the fixed anchor — expand leftward
            frame.origin.x = frame.maxX - clampedWidth
        }
        // Left: left screen edge is the fixed anchor — origin.x stays the same
        frame.size.width = clampedWidth
        window.setFrame(frame, display: true)
    }

    private func panelResizeEnded(width: CGFloat) {
        ShortcutSettings.shared.panelWidth = window?.frame.width ?? width
        Log.window.info("[SidePanelController] panel resized to \(ShortcutSettings.shared.panelWidth, privacy: .public)pt")
    }

    // MARK: - Frame Calculation

    /// A safe off-screen parking position that can't overlap any monitor in any arrangement.
    /// The window is invisible (alphaValue = 0) and ignoresMouseEvents when parked here.
    private func parkedFrame(panelWidth: CGFloat) -> NSRect {
        NSRect(x: -panelWidth - 1000, y: -10000, width: panelWidth, height: 100)
    }

    /// Returns (shown, hidden) frames for the given edge side using the persisted panel width.
    private func panelFrames(visibleFrame: NSRect, side: EdgeSide) -> (shown: NSRect, hidden: NSRect) {
        let width = ShortcutSettings.shared.panelWidth
        let shown: NSRect
        let hidden: NSRect
        switch side {
        case .right:
            shown = NSRect(x: visibleFrame.maxX - width, y: visibleFrame.minY,
                           width: width, height: visibleFrame.height)
            hidden = NSRect(x: visibleFrame.maxX, y: visibleFrame.minY,
                            width: width, height: visibleFrame.height)
        case .left:
            shown = NSRect(x: visibleFrame.minX, y: visibleFrame.minY,
                           width: width, height: visibleFrame.height)
            hidden = NSRect(x: visibleFrame.minX - width, y: visibleFrame.minY,
                            width: width, height: visibleFrame.height)
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

    /// Frame of the resize handle within the container view.
    /// Centered on the visible card boundary (PageLayout uses 12pt horizontal padding).
    private static func resizeHandleFrame(for side: EdgeSide, containerWidth: CGFloat, height: CGFloat) -> NSRect {
        // The visible card edge is 12pt from the window edge (PageLayout.padding(.horizontal, 12)).
        // Center the handle on that boundary so the cursor appears on the visible border.
        let cardInset: CGFloat = 12
        let w = ResizeHandleView.handleWidth
        switch side {
        case .right:
            return NSRect(x: cardInset - w / 2, y: 0, width: w, height: height)
        case .left:
            return NSRect(x: containerWidth - cardInset - w / 2, y: 0, width: w, height: height)
        }
    }

    /// Autoresizing mask for the resize handle so it stays on the inner edge as the container resizes.
    private static func resizeHandleAutoresizing(for side: EdgeSide) -> NSView.AutoresizingMask {
        switch side {
        case .right: [.height, .maxXMargin] // stays glued to left edge
        case .left: [.height, .minXMargin] // stays glued to right edge
        }
    }

    // MARK: - Helpers

    /// Reactivate the app that was frontmost before the panel appeared,
    /// so its mouse events go through the global monitor again.
    /// Skips restoration if another EdgeMark window (e.g. Settings, Update) is key.
    private func restorePreviousApp() {
        let hasOtherKeyWindow = NSApp.windows.contains { $0 !== window && $0.isKeyWindow }
        if !hasOtherKeyWindow {
            if let app = previousApp {
                let name = app.localizedName ?? "unknown"
                Log.window.debug("[SidePanelController] restoring focus to \(name, privacy: .public)")
            } else {
                Log.window.debug("[SidePanelController] no previousApp to restore")
            }
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

// MARK: - ResizeHandleView

/// Invisible 8pt-wide strip centered on the panel's visible inner card edge. Dragging it resizes the panel.
private final class ResizeHandleView: NSView {
    static let handleWidth: CGFloat = 8
    static let minWidth: CGFloat = 400

    var side: EdgeSide = .right
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnded: ((CGFloat) -> Void)?

    private var dragStartX: CGFloat = 0
    private var dragStartWidth: CGFloat = 0

    override func mouseDown(with _: NSEvent) {
        dragStartX = NSEvent.mouseLocation.x
        dragStartWidth = window?.frame.width ?? ShortcutSettings.shared.panelWidth
        let w = dragStartWidth
        let s = side.rawValue
        Log.window.debug("[ResizeHandleView] drag began — startWidth: \(w, privacy: .public)pt side: \(s, privacy: .public)")
    }

    override func mouseDragged(with _: NSEvent) {
        let deltaX = NSEvent.mouseLocation.x - dragStartX
        let newWidth: CGFloat = switch side {
        case .right:
            // Left edge draggable: moving left (negative deltaX) widens the panel
            max(Self.minWidth, dragStartWidth - deltaX)
        case .left:
            // Right edge draggable: moving right (positive deltaX) widens the panel
            max(Self.minWidth, dragStartWidth + deltaX)
        }
        onDrag?(newWidth)
    }

    override func mouseUp(with _: NSEvent) {
        let finalWidth = window?.frame.width ?? ShortcutSettings.shared.panelWidth
        Log.window.debug("[ResizeHandleView] drag ended — finalWidth: \(finalWidth, privacy: .public)pt")
        onDragEnded?(finalWidth)
        NSCursor.arrow.set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas {
            removeTrackingArea(ta)
        }
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
}
