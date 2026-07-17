import AppKit
import OSLog
import SwiftUI

/// Owns the peek preview window and the hover timing state. One coordinator
/// is instantiated per panel and injected into the SwiftUI environment so
/// every row modifier can drive it.
@Observable
final class PeekCoordinator {
    // MARK: - Tuning

    /// Hover dwell before the preview appears. Read from settings on each
    /// schedule so changes take effect without restarting.
    private var showDelay: TimeInterval {
        AppSettings.shared.hoverPeekDelay.seconds
    }

    /// Grace period after mouseExited before the preview hides. Lets the
    /// cursor cross the gap from the row to the preview window.
    static let dismissDelay: TimeInterval = 0.12

    // MARK: - State

    private let controller = PeekWindowController()
    private var pendingShowWorkItem: DispatchWorkItem?
    private var dismissWorkItem: DispatchWorkItem?

    /// ID of the row currently scheduled (or shown). Used to suppress
    /// duplicate `scheduleShow` calls from the same row's re-enter.
    private var scheduledID: NoteStore.SelectableID?
    /// Frame of the panel window (screen coords) — refreshed on every
    /// `scheduleShow` call. Used by `isMouseInUnion` and by the show() math.
    private var panelFrame: NSRect = .zero
    /// When true, all scheduling is a no-op (used while a context menu is
    /// open, during a marquee drag, or when the editor is focused).
    var suppressPeek: Bool = false
    /// True when the current preview was triggered by the Space key
    /// (keyboard Quick Look). Used by `updateForSelectionChange` to
    /// keep the preview in sync with arrow-key navigation.
    private(set) var isKeyboardTriggered: Bool = false

    init() {
        controller.onMouseEntered = { [weak self] in
            self?.cancelDismiss()
        }
        controller.onMouseExited = { [weak self] in
            self?.scheduleDismiss()
        }

        // Dismiss on ESC pressed inside the preview window.
        NotificationCenter.default.addObserver(
            forName: .peekEscPressed,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            self?.dismissNow()
        }

        // Dismiss when a preview-related toggle is flipped off in Settings.
        // Only dismiss the preview that the just-disabled trigger owns:
        // hover off → dismiss hover-driven; space off → dismiss keyboard-driven.
        NotificationCenter.default.addObserver(
            forName: .previewSettingsChanged,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            guard let self else { return }
            let hoverOn = AppSettings.shared.hoverPeekEnabled
            let spaceOn = AppSettings.shared.spaceToPreviewEnabled
            if isKeyboardTriggered, !spaceOn {
                dismissNow()
            } else if !isKeyboardTriggered, !hoverOn {
                dismissNow()
            }
        }
    }

    // MARK: - Public entry points

    /// The peek preview window's current screen frame, or `nil` if not showing.
    /// Used by `SidePanelController.isMouseInPanel()` to extend the hover region.
    var peekWindowFrame: NSRect? {
        controller.window?.frame
    }

    /// Schedule the preview to appear after `showDelay`. Called from a row's
    /// `mouseEntered`. Cancels any pending dismiss. If the row is the same
    /// as the already-scheduled one, this is a no-op.
    func scheduleShow(
        id: NoteStore.SelectableID,
        content: PeekContent,
        anchorRowScreen: NSRect,
        panelFrame: NSRect,
        side: EdgeSide,
        screen: NSScreen,
        cursorAtEnter: NSPoint,
    ) {
        let enabled = AppSettings.shared.hoverPeekEnabled
        let suppressed = suppressPeek
        Log.peek.debug("[PeekCoordinator] scheduleShow — enabled=\(enabled) suppress=\(suppressed) id=\(String(describing: id))")
        // Global kill-switch — settings toggle, editor focus, trash, etc.
        guard AppSettings.shared.hoverPeekEnabled else {
            Log.peek.debug("[PeekCoordinator] scheduleShow — BLOCKED hoverPeekEnabled=false")
            return
        }
        guard !suppressPeek else {
            Log.peek.debug("[PeekCoordinator] scheduleShow — BLOCKED suppressPeek=true")
            return
        }

        // Skip duplicate scheduling from the same row re-entering.
        if scheduledID == id, controller.isShowing {
            return
        }

        cancelDismiss()
        pendingShowWorkItem?.cancel()
        self.panelFrame = panelFrame

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Cursor may have left the row during the debounce — abort.
            let inRow = isMouseStillOnRow(panelFrame: panelFrame, cursorAtEnter: cursorAtEnter)
            Log.peek.debug("[PeekCoordinator] timer fired — inRow=\(inRow) cursor=\(NSEvent.mouseLocation.debugDescription) panel=\(panelFrame.debugDescription) enterY=\(cursorAtEnter.y)")
            guard inRow else {
                scheduledID = nil
                return
            }
            scheduledID = id
            isKeyboardTriggered = false // hover now drives the preview
            let tint = AppSettings.shared.panelTint.color
            controller.show(
                content: content,
                anchorRow: anchorRowScreen,
                panelFrame: panelFrame,
                side: side,
                screen: screen,
                tint: tint,
            )
        }
        pendingShowWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + showDelay, execute: work)
    }

    /// Schedule a hide after `dismissDelay`. Fires the hide only if the
    /// cursor is still outside the gap + preview union region.
    /// If a show timer is pending and the cursor is still in the panel,
    /// the show timer is left running — its own `isMouseInRow` check will
    /// abort if the cursor moved to a different row.
    func scheduleDismiss() {
        cancelDismiss()
        let showing = controller.isShowing
        Log.peek.debug("[PeekCoordinator] scheduleDismiss — cursor=\(NSEvent.mouseLocation.debugDescription) showing=\(showing)")

        // Don't cancel the pending show timer if the cursor is still inside
        // the panel — the user is just moving between rows. The show timer's
        // isMouseInRow check will abort if the cursor is no longer on the
        // target row when it fires.
        if !panelFrame.contains(NSEvent.mouseLocation) {
            pendingShowWorkItem?.cancel()
            pendingShowWorkItem = nil
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let inUnion = isMouseInUnion()
            Log.peek.debug("[PeekCoordinator] dismissTimer — inUnion=\(inUnion) showing=\(controller.isShowing) cursor=\(NSEvent.mouseLocation.debugDescription)")
            if inUnion {
                // Cursor is in the gap or preview window — keep alive but
                // poll until it leaves so we don't get stuck open.
                if controller.isShowing {
                    rescheduleDismiss()
                }
                return
            }
            scheduledID = nil
            controller.hide()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dismissDelay, execute: work)
    }

    /// Re-check the cursor position after a short delay. If the cursor has
    /// left the union region, dismiss. Otherwise keep re-checking.
    private func rescheduleDismiss() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let inUnion = isMouseInUnion()
            Log.peek.debug("[PeekCoordinator] recheckDismiss — inUnion=\(inUnion) cursor=\(NSEvent.mouseLocation.debugDescription)")
            if inUnion {
                if controller.isShowing {
                    rescheduleDismiss()
                }
                return
            }
            scheduledID = nil
            controller.hide()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Called by the preview window's `mouseEntered` handler so the grace
    /// timer doesn't fire while the cursor is inside the preview.
    func cancelDismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    /// Synchronous dismiss — used when the panel hides, the editor opens,
    /// trash activates, or the feature is toggled off.
    func dismissNow() {
        pendingShowWorkItem?.cancel()
        pendingShowWorkItem = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        scheduledID = nil
        isKeyboardTriggered = false
        controller.hideImmediately()
    }

    // MARK: - Keyboard-triggered peek (Space to preview)

    /// Toggle the preview for the given content. If already showing this
    /// content, dismiss. Otherwise, show immediately (no hover delay).
    /// Used by the Space-to-preview keyboard shortcut.
    func triggerPeek(content: PeekContent, panelFrame: NSRect) {
        // Respect the Space-to-preview kill switch (independent from hover).
        guard AppSettings.shared.spaceToPreviewEnabled else { return }
        guard !suppressPeek else { return }

        // Toggle off: already showing this exact content.
        if controller.isShowing, scheduledID == content.id {
            Log.peek.debug("[PeekCoordinator] triggerPeek — TOGGLE OFF id=\(String(describing: content.id))")
            dismissNow()
            return
        }

        Log.peek.debug("[PeekCoordinator] triggerPeek — SHOW id=\(String(describing: content.id))")
        cancelDismiss()
        pendingShowWorkItem?.cancel()
        pendingShowWorkItem = nil
        self.panelFrame = panelFrame
        scheduledID = content.id
        isKeyboardTriggered = true

        let side = ShortcutSettings.shared.edgeSide
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let tint = AppSettings.shared.panelTint.color
        // anchorRow is unused by computeFrame; pass panelFrame as a placeholder.
        controller.show(
            content: content,
            anchorRow: panelFrame,
            panelFrame: panelFrame,
            side: side,
            screen: screen,
            tint: tint,
        )
    }

    /// Update the preview content when the selection changes via keyboard
    /// (arrow keys). Only acts if the current preview was keyboard-triggered;
    /// hover-driven previews update via `mouseEntered` on the new row.
    func updateForSelectionChange(content: PeekContent) {
        guard isKeyboardTriggered, controller.isShowing else { return }
        guard scheduledID != content.id else { return }
        Log.peek.debug("[PeekCoordinator] updateForSelectionChange — id=\(String(describing: content.id))")
        cancelDismiss()
        scheduledID = content.id
        let tint = AppSettings.shared.panelTint.color
        let side = ShortcutSettings.shared.edgeSide
        let screen = NSScreen.main ?? NSScreen.screens.first!
        controller.show(
            content: content,
            anchorRow: panelFrame,
            panelFrame: panelFrame,
            side: side,
            screen: screen,
            tint: tint,
        )
    }

    // MARK: - Geometry

    /// Union region: gap strip + preview window frame. The panel itself is
    /// intentionally excluded — row-to-row transitions are handled by
    /// `mouseEntered → cancelDismiss`, so the preview should dismiss when the
    /// cursor lands anywhere else (header, footer, empty space below rows).
    func isMouseInUnion() -> Bool {
        let cursor = NSEvent.mouseLocation
        if controller.window?.frame.contains(cursor) == true {
            return true
        }
        if gapStrip().contains(cursor) {
            return true
        }
        return false
    }

    /// Whether the cursor is still hovering over the row list area.
    /// Uses the panel frame for horizontal bounds (reliable) and checks
    /// the cursor hasn't drifted far from the Y position captured at
    /// mouseEntered time (avoids stale named-coordinate-space rects).
    private func isMouseStillOnRow(panelFrame: NSRect, cursorAtEnter: NSPoint) -> Bool {
        let cursor = NSEvent.mouseLocation
        // Must be horizontally within the panel (with margin for the resize handle area).
        let hInset = panelFrame.insetBy(dx: -16, dy: 0)
        guard hInset.contains(cursor) else { return false }
        // Must be vertically near where the cursor entered the row.
        // 60pt tolerance ≈ one full row height of drift from scroll or movement.
        return abs(cursor.y - cursorAtEnter.y) < 60
    }

    /// The 12pt-wide strip between the panel's inner edge and the preview
    /// window's outer edge. Keeps the hover alive while the cursor crosses.
    private func gapStrip() -> NSRect {
        guard !panelFrame.isEmpty else { return .zero }
        let side = ShortcutSettings.shared.edgeSide
        let gap = PeekWindowController.gap
        switch side {
        case .right:
            return NSRect(
                x: panelFrame.minX - gap,
                y: panelFrame.minY,
                width: gap,
                height: panelFrame.height,
            )
        case .left:
            return NSRect(
                x: panelFrame.maxX,
                y: panelFrame.minY,
                width: gap,
                height: panelFrame.height,
            )
        }
    }
}
