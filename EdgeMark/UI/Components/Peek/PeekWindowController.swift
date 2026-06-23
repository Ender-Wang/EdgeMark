import Cocoa
import SwiftUI

// MARK: - Peek Content payload

/// Payload handed to the peek window on show / update. Folders pre-resolve
/// their subfolders and recent-note list (sorted by `modifiedAt` desc, capped
/// to 8) so the view can render synchronously without re-querying the store.
enum PeekContent: Equatable {
    case note(Note)
    case folder(Folder, [Folder], [Note])

    var id: NoteStore.SelectableID {
        switch self {
        case let .note(note): .note(note.id)
        case let .folder(folder, _, _): .folder(folder.name)
        }
    }
}

// MARK: - PeekWindow

/// Borderless floating window used for the peek preview. Level is set to
/// `.floating + 1` so it sits above the panel (which is at `.floating`).
/// `canBecomeKey` returns false so the panel stays key while the user
/// scrolls inside the preview.
final class PeekWindow: NSWindow {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

// MARK: - PeekWindowController

final class PeekWindowController: NSWindowController {
    /// Gap between the panel's inner edge and the preview window.
    static let gap: CGFloat = 4

    private var animationGeneration = 0
    private var isAnimating = false
    private var contentHostingView: NSView?
    private var hostingView: NSHostingView<AnyView>?

    /// Closure the window calls on mouseEntered over its content view.
    var onMouseEntered: (() -> Void)?
    /// Closure the window calls on mouseExited over its content view.
    var onMouseExited: (() -> Void)?

    // MARK: - Lifecycle

    init() {
        // Park off-screen; show() will reposition before the window becomes visible.
        let window = PeekWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 400, height: 600),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: Int(NSWindow.Level.floating.rawValue) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = false
        window.alphaValue = 0

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Whether a preview is currently being shown (window ordered and visible).
    var isShowing: Bool {
        (window?.alphaValue ?? 0) > 0
    }

    // MARK: - Show / Update

    /// Present the preview with the given content, positioned on the opposite
    /// side of the panel. `anchorRow` and `panelFrame` are in screen coordinates.
    /// If a preview is already visible with the same content, this is a no-op.
    /// If the content differs, the window swaps content in place (no animation).
    func show(
        content: PeekContent,
        anchorRow: NSRect,
        panelFrame: NSRect,
        side: EdgeSide,
        screen: NSScreen,
        tint: NSColor?,
    ) {
        guard let window else { return }

        // Already showing this exact content — skip reposition / animation churn.
        if isShowing, hostingView != nil, let current = currentContent, current == content {
            return
        }

        let targetFrame = Self.computeFrame(
            content: content,
            anchorRow: anchorRow,
            panelFrame: panelFrame,
            side: side,
            screen: screen,
        )

        let isNewlyShown = !isShowing

        if isNewlyShown {
            // Build the content, position the window, and fade in.
            installOrUpdateContent(content: content, tint: tint)
            window.setFrame(targetFrame, display: true)
            window.orderFront(nil)
            isAnimating = true
            let gen = animationGeneration &+ 1
            animationGeneration = gen

            // Always use fade for peek transitions.
            window.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            } completionHandler: { [weak self] in
                guard let self, animationGeneration == gen else { return }
                isAnimating = false
            }
        } else {
            // Content swap while the window is already visible: update
            // the content directly without animation. Avoiding any
            // fade-out/fade-in cycle eliminates flash when hovering
            // through multiple rows quickly.
            installOrUpdateContent(content: content, tint: tint)
            window.setFrame(targetFrame, display: true)
        }
    }

    /// Dismiss the preview with a fade-out. Idempotent.
    func hide() {
        guard let window, isShowing else { return }
        isAnimating = true
        let gen = animationGeneration &+ 1
        animationGeneration = gen

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, animationGeneration == gen else { return }
            window.orderOut(nil)
            isAnimating = false
        }
    }

    /// Synchronous dismiss used by the coordinator on hard interrupts
    /// (panel hide, settings toggle off, editor open). Skips animation.
    func hideImmediately() {
        guard let window else { return }
        animationGeneration &+= 1
        isAnimating = false
        window.orderOut(nil)
        window.alphaValue = 0
    }

    // MARK: - Content

    private var currentContent: PeekContent?

    private func installOrUpdateContent(content: PeekContent, tint: NSColor?) {
        let rootView = AnyView(
            PeekChrome(tint: tint) {
                PeekContentView(content: content)
            }
            .environment(L10n.shared),
        )
        if let existing = hostingView {
            existing.rootView = rootView
        } else {
            let host = NSHostingView(rootView: rootView)
            host.wantsLayer = true
            host.layer?.cornerRadius = 10
            host.layer?.masksToBounds = true
            host.frame = NSRect(origin: .zero, size: window?.contentRect(forFrameRect: window!.frame).size ?? .zero)
            host.autoresizingMask = [.width, .height]

            // Mouse tracking so the coordinator can cancel the dismiss timer
            // when the cursor enters the preview window.
            let trackingArea = NSTrackingArea(
                rect: host.bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil,
            )
            host.addTrackingArea(trackingArea)

            window?.contentView = host
            contentHostingView = host
            hostingView = host
        }
        currentContent = content
    }

    override func mouseEntered(with _: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with _: NSEvent) {
        onMouseExited?()
    }

    // MARK: - Frame math

    /// Position the preview side-by-side with the panel. The preview window
    /// is 80% of the panel's width and height, centered vertically, with a
    /// small gap from the panel edge.
    private static func computeFrame(
        content _: PeekContent,
        anchorRow _: NSRect,
        panelFrame: NSRect,
        side: EdgeSide,
        screen _: NSScreen,
    ) -> NSRect {
        let width = panelFrame.width * 0.8
        let height = panelFrame.height * 0.8

        let x: CGFloat = switch side {
        case .right:
            panelFrame.minX - gap - width
        case .left:
            panelFrame.maxX + gap
        }

        // Vertically center relative to the panel.
        let y = panelFrame.minY + (panelFrame.height - height) / 2

        return NSRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - PeekChrome

/// Visual wrapper applied around the peek content: translucent material
/// background (mirrors the panel card), rounded 10pt corners, and an ESC
/// shortcut. No extra padding — the content views handle their own spacing.
private struct PeekChrome<Content: View>: View {
    let tint: NSColor?
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background {
                VisualEffectView(tint: tint, material: AppSettings.shared.panelStyle.material)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onExitCommand {
                // Dismiss on ESC. PeekCoordinator watches for hide() and clears state.
                NotificationCenter.default.post(name: .peekEscPressed, object: nil)
            }
    }
}

extension Notification.Name {
    static let peekEscPressed = Notification.Name("peekEscPressed")
}
