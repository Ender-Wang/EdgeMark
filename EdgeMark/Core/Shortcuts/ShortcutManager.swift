import Carbon
import Foundation
import OSLog

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
        Log.shortcuts.info("[ShortcutManager] re-registering shortcut")
        unregisterShortcuts()
        registerShortcuts()
    }

    // MARK: - Register / Unregister

    private func registerShortcuts() {
        guard let shortcut = ShortcutSettings.shared.togglePanelShortcut else {
            Log.shortcuts.info("[ShortcutManager] no shortcut configured, skipping registration")
            return
        }

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
            Log.shortcuts.info("[ShortcutManager] registered hotkey")
        } else {
            Log.shortcuts.error("[ShortcutManager] failed to register hotkey (status: \(status))")
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
        Log.shortcuts.debug("[ShortcutManager] hotkey pressed")
        toggleAction?()
    }

    private func unregisterShortcuts() {
        Log.shortcuts.debug("[ShortcutManager] unregistered hotkey")
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
