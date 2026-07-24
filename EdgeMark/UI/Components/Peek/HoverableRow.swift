import AppKit
import OSLog
import SwiftUI

// MARK: - HoverableRow Modifier

/// Attaches hover-to-peek tracking to a note or folder row. On mouse enter,
/// schedules a preview window via `PeekCoordinator`; on exit, schedules a
/// dismiss. Short-circuits when the feature is disabled, the editor is open,
/// trash is active, or a marquee drag is in progress.
struct HoverableRowModifier: ViewModifier {
    let id: NoteStore.SelectableID
    let content: PeekContent

    @Environment(NoteStore.self) private var noteStore
    @Environment(PeekCoordinator.self) private var peekCoordinator

    func body(content view: Content) -> some View {
        view.background(GeometryReader { geo in
            PeekTrackingNSViewRepresentable(
                state: PeekRowState(
                    id: id,
                    content: content,
                    rowFrameInNamedSpace: geo.frame(in: .named(MarqueeCoordinateSpace.name)),
                ),
                noteStore: noteStore,
                peekCoordinator: peekCoordinator,
            )
        })
    }
}

// MARK: - State Holder

/// Reference-type holder for the row's current identity, content, and frame.
/// Updated on every SwiftUI view update so the NSTrackingArea callbacks
/// always read the latest values without recreating the NSView.
final class PeekRowState {
    var id: NoteStore.SelectableID
    var content: PeekContent
    var rowFrameInNamedSpace: CGRect

    init(id: NoteStore.SelectableID, content: PeekContent, rowFrameInNamedSpace: CGRect) {
        self.id = id
        self.content = content
        self.rowFrameInNamedSpace = rowFrameInNamedSpace
    }
}

// MARK: - NSViewRepresentable

/// Bridges SwiftUI into an `NSView` that owns an `NSTrackingArea` for
/// precise mouseEntered / mouseExited callbacks on the row.
struct PeekTrackingNSViewRepresentable: NSViewRepresentable {
    let state: PeekRowState
    let noteStore: NoteStore
    let peekCoordinator: PeekCoordinator

    func makeNSView(context _: Context) -> PeekTrackingNSView {
        let view = PeekTrackingNSView()
        view.state = state
        view.noteStore = noteStore
        view.peekCoordinator = peekCoordinator
        return view
    }

    func updateNSView(_ nsView: PeekTrackingNSView, context _: Context) {
        // Keep references and tracking area in sync with the latest row data.
        nsView.state = state
        nsView.noteStore = noteStore
        nsView.peekCoordinator = peekCoordinator
        nsView.refreshTrackingArea()
    }
}

// MARK: - Tracking NSView

/// Transparent `NSView` that installs an `NSTrackingArea` matching the row's
/// bounds. On mouse enter, converts the row's frame to screen coordinates
/// and asks the coordinator to schedule a preview. On mouse exit, asks the
/// coordinator to schedule a dismiss.
final class PeekTrackingNSView: NSView {
    var state: PeekRowState?
    var noteStore: NoteStore?
    var peekCoordinator: PeekCoordinator?

    override var acceptsFirstResponder: Bool {
        false
    }

    override var isFlipped: Bool {
        true
    } // match SwiftUI's top-left origin

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }

    func refreshTrackingArea() {
        for ta in trackingAreas {
            removeTrackingArea(ta)
        }
        let b = bounds
        let hasWindow = window != nil
        guard b.width > 0, b.height > 0 else {
            Log.peek.debug("[PeekTracking] refreshTrackingArea — SKIP bounds=\(b.debugDescription)")
            return
        }
        Log.peek.debug("[PeekTracking] refreshTrackingArea — bounds=\(b.debugDescription) window=\(hasWindow)")
        addTrackingArea(NSTrackingArea(
            rect: b,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil,
        ))
    }

    // MARK: Mouse events

    override func mouseEntered(with _: NSEvent) {
        Log.peek.debug("[PeekTracking] mouseEntered — state=\(self.state != nil) noteStore=\(self.noteStore != nil) coord=\(self.peekCoordinator != nil)")
        guard let state, let noteStore, let peekCoordinator else { return }

        // --- short-circuit conditions ---
        guard AppSettings.shared.hoverPeekEnabled else {
            Log.peek.debug("[PeekTracking] mouseEntered — SKIP hoverPeekEnabled=false")
            return
        }
        guard noteStore.selectedNote == nil else {
            Log.peek.debug("[PeekTracking] mouseEntered — SKIP editor open")
            return
        }
        guard !noteStore.showTrash else {
            Log.peek.debug("[PeekTracking] mouseEntered — SKIP trash active")
            return
        }
        guard !noteStore.pendingEditorFind else {
            Log.peek.debug("[PeekTracking] mouseEntered — SKIP find bar")
            return
        }
        guard !peekCoordinator.suppressPeek else {
            Log.peek.debug("[PeekTracking] mouseEntered — SKIP suppressPeek")
            return
        }

        // Convert the row's frame from the marquee named coordinate space
        // to screen coordinates for the peek window positioning math.
        guard let win = window else { return }
        let screenRect = win.convertToScreen(convert(state.rowFrameInNamedSpace, from: nil))
        let panelFrame = win.convertToScreen(win.contentView?.bounds ?? win.frame)
        guard let screen = win.screen ?? NSScreen.main else { return }

        // Capture cursor position at enter time as a reliable screen-space reference.
        let cursorAtEnter = NSEvent.mouseLocation

        let side = PanelSettings.shared.edgeSide
        Log.peek.debug("[PeekTracking] mouseEntered — calling scheduleShow id=\(String(describing: state.id)) side=\(side.rawValue) screenRect=\(screenRect.debugDescription) cursor=\(cursorAtEnter.debugDescription) panel=\(panelFrame.debugDescription)")
        peekCoordinator.scheduleShow(
            id: state.id,
            content: state.content,
            anchorRowScreen: screenRect,
            panelFrame: panelFrame,
            side: side,
            screen: screen,
            cursorAtEnter: cursorAtEnter,
        )
    }

    override func mouseExited(with _: NSEvent) {
        peekCoordinator?.scheduleDismiss()
    }
}

// MARK: - View extension

extension View {
    /// Attach hover-to-peek tracking to this row. The preview appears after
    /// a short dwell (`PeekCoordinator.showDelay`) and stays open while the
    /// cursor crosses into the preview window.
    func hoverableRow(id: NoteStore.SelectableID, content: PeekContent) -> some View {
        modifier(HoverableRowModifier(id: id, content: content))
    }
}
