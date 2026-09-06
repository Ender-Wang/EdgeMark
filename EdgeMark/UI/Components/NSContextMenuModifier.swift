import Cocoa
import SwiftUI

// MARK: - Singleton menu action dispatcher

/// Single long-lived target for all NSMenuItem closure actions.
/// Uses tag-based dispatch: each menu item gets a unique tag mapped to its closure.
///
/// This avoids two pitfalls with per-item action targets:
/// 1. `NSMenuItem.target` is **weak** — per-item objects can be freed before the action fires.
/// 2. SwiftUI may recreate the NSViewRepresentable host during a popup, releasing any
///    retained references stored on the old view.
///
/// The singleton lives for the process lifetime, so neither issue applies.
@objc(EMMenuDispatch)
private final class MenuDispatch: NSObject {
    static let shared = MenuDispatch()

    private var actions: [Int: () -> Void] = [:]
    private var nextTag = 1

    /// Register a closure and return a unique tag for the menu item.
    func register(_ action: @escaping () -> Void) -> Int {
        let tag = nextTag
        nextTag += 1
        actions[tag] = action
        return tag
    }

    /// Remove all registered closures (call after the menu dismisses).
    func clear() {
        actions.removeAll()
        nextTag = 1
    }

    @objc(run:)
    func run(_ sender: NSMenuItem) {
        actions[sender.tag]?()
    }
}

// MARK: - NSMenu Context Menu Modifier

/// Attaches an NSMenu as the right-click context menu for any SwiftUI view.
/// Unlike SwiftUI's `.contextMenu`, NSMenu items reliably show SF Symbol icons on macOS.
struct NSContextMenuModifier: ViewModifier {
    let menuBuilder: () -> NSMenu

    func body(content: Content) -> some View {
        content.overlay {
            NSContextMenuOverlay(menuBuilder: menuBuilder)
        }
    }
}

extension View {
    /// Attach an NSMenu as the right-click context menu (icons render reliably).
    func nsContextMenu(_ menuBuilder: @escaping () -> NSMenu) -> some View {
        modifier(NSContextMenuModifier(menuBuilder: menuBuilder))
    }
}

// MARK: - NSViewRepresentable overlay

private struct NSContextMenuOverlay: NSViewRepresentable {
    let menuBuilder: () -> NSMenu

    func makeNSView(context _: Context) -> ContextMenuCatcher {
        ContextMenuCatcher()
    }

    func updateNSView(_ nsView: ContextMenuCatcher, context _: Context) {
        nsView.menuBuilder = menuBuilder
    }

    /// Transparent NSView that intercepts right-clicks to show an NSMenu,
    /// while passing all other events (left-click, scroll, drag) through to SwiftUI.
    final class ContextMenuCatcher: NSView {
        var menuBuilder: (() -> NSMenu)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only intercept right-clicks; pass everything else through
            if let event = NSApp.currentEvent, event.type == .rightMouseDown {
                let local = convert(point, from: superview)
                if bounds.contains(local) {
                    return self
                }
            }
            return nil
        }

        override func rightMouseDown(with event: NSEvent) {
            if let menu = menuBuilder?() {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
                MenuDispatch.shared.clear()
            }
        }
    }
}

// MARK: - Row Click Modifier (single + double click, no SwiftUI delay)

/// Attaches an AppKit-driven click handler to a row.
/// SwiftUI's `.onTapGesture(count: 1)` waits for the multi-tap window before firing,
/// which feels laggy. AppKit delivers each `mouseDown` immediately with `clickCount`
/// indicating 1 or 2 — so we fire the single-click action right away and the
/// double-click action when the second click arrives.
struct RowClickModifier: ViewModifier {
    let onSingle: (NSEvent.ModifierFlags) -> Void
    let onDouble: () -> Void
    let dragItem: NoteStore.DragItem?
    let dragPreviewLabel: String?

    func body(content: Content) -> some View {
        content.overlay {
            RowClickOverlay(
                onSingle: onSingle,
                onDouble: onDouble,
                dragItem: dragItem,
                dragPreviewLabel: dragPreviewLabel,
            )
        }
    }
}

extension View {
    /// Attach an instant single/double click handler.
    /// Single click fires immediately on mouse-down with the active modifier flags.
    /// Double click fires when the second click arrives.
    func rowClick(
        onSingle: @escaping (NSEvent.ModifierFlags) -> Void,
        onDouble: @escaping () -> Void,
        dragItem: NoteStore.DragItem? = nil,
        dragPreviewLabel: String? = nil,
    ) -> some View {
        modifier(
            RowClickModifier(
                onSingle: onSingle,
                onDouble: onDouble,
                dragItem: dragItem,
                dragPreviewLabel: dragPreviewLabel,
            ),
        )
    }
}

private struct RowClickOverlay: NSViewRepresentable {
    let onSingle: (NSEvent.ModifierFlags) -> Void
    let onDouble: () -> Void
    let dragItem: NoteStore.DragItem?
    let dragPreviewLabel: String?

    func makeNSView(context _: Context) -> RowClickCatcher {
        RowClickCatcher()
    }

    func updateNSView(_ nsView: RowClickCatcher, context _: Context) {
        nsView.onSingle = onSingle
        nsView.onDouble = onDouble
        nsView.dragItem = dragItem
        nsView.dragPreviewLabel = dragPreviewLabel
    }

    /// Transparent NSView that intercepts only left-mouse-down (so right-clicks,
    /// scrolls, hovers and drags continue to flow into SwiftUI as normal).
    final class RowClickCatcher: NSView, NSDraggingSource {
        var onSingle: ((NSEvent.ModifierFlags) -> Void)?
        var onDouble: (() -> Void)?
        var dragItem: NoteStore.DragItem?
        var dragPreviewLabel: String?
        private var mouseDownLocation: NSPoint?
        private var startedDragging = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only intercept left-clicks; pass everything else through.
            if let event = NSApp.currentEvent, event.type == .leftMouseDown {
                let local = convert(point, from: superview)
                if bounds.contains(local) {
                    return self
                }
            }
            return nil
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownLocation = convert(event.locationInWindow, from: nil)
            startedDragging = false
            // clickCount is 1 for the first click and 2 for a quick second click.
            // We fire each immediately — selection is harmless before a follow-up
            // open, and openNote/navigate clear the selection anyway.
            if event.clickCount >= 2 {
                onDouble?()
            } else {
                onSingle?(event.modifierFlags)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard !startedDragging,
                  let dragItem,
                  let mouseDownLocation
            else { return }
            let currentLocation = convert(event.locationInWindow, from: nil)
            guard hypot(currentLocation.x - mouseDownLocation.x, currentLocation.y - mouseDownLocation.y) >= 4 else { return }

            startedDragging = true
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(
                EdgeMarkDragPayload.data(for: dragItem),
                forType: NSPasteboard.PasteboardType(EdgeMarkDragPayload.typeIdentifier),
            )
            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            let preview = dragPreviewImage(for: dragItem, label: dragPreviewLabel)
            let location = convert(event.locationInWindow, from: nil)
            let previewFrame = NSRect(
                x: location.x + 8,
                y: location.y - preview.size.height / 2,
                width: preview.size.width,
                height: preview.size.height,
            )
            draggingItem.setDraggingFrame(previewFrame, contents: preview)
            let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        override func mouseUp(with _: NSEvent) {
            mouseDownLocation = nil
            startedDragging = false
        }

        func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
            .move
        }

        func ignoreModifierKeys(for _: NSDraggingSession) -> Bool {
            true
        }

        private func dragPreviewImage(for item: NoteStore.DragItem, label: String?) -> NSImage {
            let size = NSSize(width: 220, height: 34)
            let image = NSImage(size: size)
            let iconName: String
            let fallbackLabel: String
            switch item {
            case .note:
                iconName = "doc.text"
                fallbackLabel = "Note"
            case let .folder(path):
                iconName = "folder.fill"
                fallbackLabel = (path as NSString).lastPathComponent
            }
            let displayLabel = label ?? fallbackLabel
            image.lockFocus()
            defer { image.unlockFocus() }

            let background = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 8, yRadius: 8)
            NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
            background.fill()
            NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
            background.stroke()

            let iconRect = NSRect(x: 10, y: 8, width: 18, height: 18)
            NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.draw(
                in: iconRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil,
            )
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
            ]
            NSString(string: displayLabel).draw(
                in: NSRect(x: 36, y: 8, width: 174, height: 18),
                withAttributes: attributes,
            )
            return image
        }
    }
}

// MARK: - NSMenu Builder Helpers

extension NSMenu {
    /// Pop up this menu (built with addActionItem) at a point in a view without an NSEvent.
    /// Blocks until dismissed, then clears MenuDispatch closures.
    func popUpAtPoint(_ point: NSPoint, in view: NSView) {
        popUp(positioning: nil, at: point, in: view)
        MenuDispatch.shared.clear()
    }

    /// Pop up this menu at a screen-coordinate point.
    /// AppKit automatically flips the menu above the cursor when near the bottom of the screen.
    func popUpAtScreenPoint(_ screenPoint: NSPoint) {
        popUp(positioning: nil, at: screenPoint, in: nil)
        MenuDispatch.shared.clear()
    }

    /// Add a menu item with an SF Symbol icon and a closure action.
    @discardableResult
    func addActionItem(
        title: String,
        icon: String,
        action: @escaping () -> Void,
    ) -> NSMenuItem {
        let tag = MenuDispatch.shared.register(action)
        let item = NSMenuItem(
            title: title,
            action: #selector(MenuDispatch.run(_:)),
            keyEquivalent: "",
        )
        item.tag = tag
        item.target = MenuDispatch.shared
        item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        addItem(item)
        return item
    }
}
