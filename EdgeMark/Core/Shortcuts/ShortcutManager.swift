import Carbon
import Foundation

/// Manages system-wide keyboard shortcuts via the Carbon Event API.
final class ShortcutManager {
    static let shared = ShortcutManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var toggleAction: (() -> Void)?

    private init() {}

    func setup(panelController: SidePanelController) {
        toggleAction = { [weak panelController] in
            panelController?.togglePanel()
        }
        registerShortcuts()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutSettingsChanged),
            name: .shortcutSettingsChanged,
            object: nil,
        )
    }

    @objc private func shortcutSettingsChanged() {
        unregisterShortcuts()
        registerShortcuts()
    }

    // MARK: - Register / Unregister

    private func registerShortcuts() {
        guard let shortcut = ShortcutSettings.shared.togglePanelShortcut else { return }

        // Signature: 'EMRK' (EdgeMark)
        let hotKeyID = EventHotKeyID(signature: OSType(0x454D_524B), id: 1)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref,
        )

        if status == noErr {
            hotKeyRef = ref
            installEventHandler()
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed),
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handleHotKeyEvent(event)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler,
        )
    }

    private func handleHotKeyEvent(_: EventRef?) {
        toggleAction?()
    }

    private func unregisterShortcuts() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        unregisterShortcuts()
        NotificationCenter.default.removeObserver(self)
    }
}
