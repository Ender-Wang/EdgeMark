import Cocoa
import SwiftUI

final class UpdateWindowController: NSWindowController {
    init(updateState: UpdateState) {
        let updateView = UpdateView()
            .environment(updateState)
        let hostingView = NSHostingView(rootView: updateView)

        let fitting = hostingView.fittingSize
        let contentSize = NSSize(
            width: max(fitting.width, 420),
            height: max(fitting.height, 100),
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
        )
        window.title = "Software Update"
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .windowBackgroundColor
        window.level = .normal
        window.hasShadow = true
        window.center()
        window.isMovableByWindowBackground = false

        super.init(window: window)

        hostingView.frame = window.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
