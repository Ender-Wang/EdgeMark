import Carbon
import Cocoa
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var shortcut: KeyboardShortcut?
    @State private var isRecording = false

    var body: some View {
        KeyRecorderRepresentable(shortcut: $shortcut, isRecording: $isRecording)
            .frame(height: 32)
    }
}

struct KeyRecorderRepresentable: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcut?
    @Binding var isRecording: Bool

    func makeNSView(context _: Context) -> KeyRecorderButton {
        let button = KeyRecorderButton()
        button.onKeyRecorded = { keyCode, modifiers in
            shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
            isRecording = false
            NotificationCenter.default.post(name: .shortcutSettingsChanged, object: nil)
        }
        button.onClear = {
            shortcut = nil
            NotificationCenter.default.post(name: .shortcutSettingsChanged, object: nil)
        }
        button.onRecordingChanged = { recording in
            isRecording = recording
        }
        return button
    }

    func updateNSView(_ nsView: KeyRecorderButton, context _: Context) {
        nsView.currentShortcut = shortcut
        nsView.isRecording = isRecording
    }
}

final class KeyRecorderButton: NSView {
    var onKeyRecorded: ((UInt16, UInt32) -> Void)?
    var onClear: (() -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?

    var currentShortcut: KeyboardShortcut? {
        didSet { needsDisplay = true }
    }

    var isRecording = false {
        didSet {
            needsDisplay = true
            if isRecording {
                window?.makeFirstResponder(self)
            }
        }
    }

    private var trackingArea: NSTrackingArea?
    private var clearButtonRect: NSRect = .zero
    private var isHoveringClear = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 6
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil,
        )
        if let trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Background
        let bgColor: NSColor = isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.08)
            : NSColor.controlBackgroundColor
        bgColor.setFill()
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        bgPath.fill()

        // Border
        let borderColor: NSColor = isRecording
            ? NSColor.controlAccentColor
            : NSColor.separatorColor
        borderColor.setStroke()
        let strokePath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        strokePath.lineWidth = isRecording ? 2 : 1
        strokePath.stroke()

        // Text
        let textRect = NSRect(x: 12, y: 0, width: bounds.width - 40, height: bounds.height)
        let text: String
        let textColor: NSColor
        let fontWeight: NSFont.Weight

        if isRecording {
            text = "Press keys\u{2026}"
            textColor = .secondaryLabelColor
            fontWeight = .regular
        } else if let shortcut = currentShortcut {
            text = shortcut.description
            textColor = .labelColor
            fontWeight = .medium
        } else {
            text = "Click to record"
            textColor = .tertiaryLabelColor
            fontWeight = .regular
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: fontWeight),
            .foregroundColor: textColor,
        ]

        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.size()
        let textY = (bounds.height - textSize.height) / 2
        attrString.draw(at: NSPoint(x: textRect.minX, y: textY))

        // Clear button (only when not recording and shortcut exists)
        if !isRecording, currentShortcut != nil {
            let clearSize: CGFloat = 16
            clearButtonRect = NSRect(
                x: bounds.width - clearSize - 8,
                y: (bounds.height - clearSize) / 2,
                width: clearSize,
                height: clearSize,
            )

            let clearColor: NSColor = isHoveringClear ? .secondaryLabelColor : .tertiaryLabelColor
            clearColor.setFill()

            let circlePath = NSBezierPath(ovalIn: clearButtonRect)
            circlePath.fill()

            NSColor.white.setStroke()
            let xSize: CGFloat = 6
            let xCenter = clearButtonRect.midX
            let yCenter = clearButtonRect.midY
            let xPath = NSBezierPath()
            xPath.move(to: NSPoint(x: xCenter - xSize / 2, y: yCenter - xSize / 2))
            xPath.line(to: NSPoint(x: xCenter + xSize / 2, y: yCenter + xSize / 2))
            xPath.move(to: NSPoint(x: xCenter + xSize / 2, y: yCenter - xSize / 2))
            xPath.line(to: NSPoint(x: xCenter - xSize / 2, y: yCenter + xSize / 2))
            xPath.lineWidth = 1.5
            xPath.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if !isRecording, currentShortcut != nil, clearButtonRect.contains(location) {
            onClear?()
            return
        }
        isRecording = true
        onRecordingChanged?(true)
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let wasHovering = isHoveringClear
        isHoveringClear = clearButtonRect.contains(location)
        if wasHovering != isHoveringClear {
            needsDisplay = true
        }
    }

    override func mouseExited(with _: NSEvent) {
        if isHoveringClear {
            isHoveringClear = false
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }

        // Bare Escape cancels recording
        if event.keyCode == UInt16(kVK_Escape),
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        {
            isRecording = false
            onRecordingChanged?(false)
            return
        }

        var carbonModifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        if event.modifierFlags.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        if event.modifierFlags.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if event.modifierFlags.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }

        // Require at least one modifier key
        if carbonModifiers != 0 {
            onKeyRecorded?(event.keyCode, carbonModifiers)
        }
    }
}
