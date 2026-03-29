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
