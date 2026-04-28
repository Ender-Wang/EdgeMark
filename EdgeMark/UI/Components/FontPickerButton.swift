import AppKit
import SwiftUI

/// A button that opens NSFontPanel and applies live updates to AppSettings.
/// As the user clicks fonts/sizes in the panel, `changeFont(_:)` fires immediately
/// and writes to `editorFontName` + `editorFontSize`, so the editor updates live.
struct FontPickerButton: NSViewRepresentable {
    let title: String

    func makeNSView(context _: Context) -> FontPickerHostView {
        FontPickerHostView(title: title)
    }

    func updateNSView(_ nsView: FontPickerHostView, context _: Context) {
        nsView.button.title = title
    }
}

final class FontPickerHostView: NSView, NSFontChanging {
    let button: NSButton
    private var fontObserver: NSObjectProtocol?

    init(title: String) {
        button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        super.init(frame: .zero)
        addSubview(button)
        button.target = self
        button.action = #selector(openPanel)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        // Keep the font panel's selection in sync with external changes
        // (e.g. user changes size via stepper while the panel is open).
        fontObserver = NotificationCenter.default.addObserver(
            forName: .editorFontChanged, object: nil, queue: .main,
        ) { _ in
            guard NSFontPanel.shared.isVisible else { return }
            NSFontManager.shared.setSelectedFont(AppSettings.shared.editorFont, isMultiple: false)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        if let fontObserver {
            NotificationCenter.default.removeObserver(fontObserver)
        }
        // NSFontManager.target is unsafe_unretained — clear it so a stale
        // pointer can't crash if changeFont(_:) fires after this view is gone.
        if NSFontManager.shared.target === self {
            NSFontManager.shared.target = nil
        }
    }

    override var intrinsicContentSize: NSSize {
        button.intrinsicContentSize
    }

    @objc private func openPanel() {
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(AppSettings.shared.editorFont, isMultiple: false)
        let panel = NSFontPanel.shared
        panel.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    func changeFont(_ sender: NSFontManager?) {
        let current = AppSettings.shared.editorFont
        let new = sender?.convert(current) ?? current
        AppSettings.shared.editorFontName = new.fontName
        AppSettings.shared.editorFontSize = Double(new.pointSize)
    }

    /// Limit the font panel to family + size (no underline/strikethrough/color).
    func validModesForFontPanel(_: NSFontPanel) -> NSFontPanel.ModeMask {
        [.face, .collection, .size]
    }
}
