import AppKit
import Foundation

// MARK: - EdgeSide

enum EdgeSide: String {
    case left
    case right
}

// MARK: - DismissalMode

/// How the panel dismisses.
/// - `.auto`: hide on mouse exit / click-outside / Space change (current behavior;
///   `isPanelPinned` still overrides all of those).
/// - `.toggle`: edge activation shows *and* sticks the panel; touching the activating
///   edge again dismisses it (after the activation-delay dwell, so a flick through the
///   edge doesn't kill the panel). Serves the copy-back-and-forth case without the pin
///   shortcut.
enum DismissalMode: String {
    case auto
    case toggle
}

// MARK: - AnimationStyle

enum AnimationStyle: String {
    /// Panel slides in/out from the screen edge (classic effect).
    /// On multi-monitor setups the slide travel may briefly appear on the adjacent display.
    case slide
    /// Panel fades in/out without any frame movement, so nothing ever appears on adjacent monitors.
    case fade
}

// MARK: - PanelSettings

/// Panel behavior + chrome: edge activation, dismissal, width, animation, and swipe
/// gestures. Split out of `ShortcutSettings` so each name matches its content. Plain
/// class (not `@Observable`); consumers snapshot into `@State` and observe notifications,
/// same pattern as `ShortcutSettings`. `isPanelPinned` is session-only (resets each
/// launch).
final class PanelSettings {
    static let shared = PanelSettings()

    /// Auto-hide when the mouse exits the panel.
    var autoHideOnMouseExit: Bool {
        didSet { UserDefaults.standard.set(autoHideOnMouseExit, forKey: autoHideKey) }
    }

    /// Delay (in seconds) before auto-hiding after mouse exit. 0 = immediate.
    var hideDelay: Double {
        didSet { UserDefaults.standard.set(hideDelay, forKey: hideDelayKey) }
    }

    /// Delay (in seconds) before edge activation triggers. 0 = immediate.
    var activationDelay: Double {
        didSet { UserDefaults.standard.set(activationDelay, forKey: activationDelayKey) }
    }

    /// Dwell (in seconds) at the activating edge before a toggle-mode re-touch
    /// dismisses the panel. UI enforces a 0.05s floor so a brush across the edge
    /// can't instantly kill the panel. Show still uses `activationDelay`.
    var toggleDismissDelay: Double {
        didSet { UserDefaults.standard.set(toggleDismissDelay, forKey: toggleDismissDelayKey) }
    }

    /// Which screen edge the panel appears from.
    var edgeSide: EdgeSide {
        didSet {
            UserDefaults.standard.set(edgeSide.rawValue, forKey: edgeSideKey)
            // Cross-post `shortcutSettingsChanged` so SidePanelController/PinButton
            // observers (which key off that name) reconfigure. Name cleanup deferred.
            NotificationCenter.default.post(name: .shortcutSettingsChanged, object: nil)
        }
    }

    /// How the panel dismisses — auto-hide or edge-toggle. See `DismissalMode`.
    var dismissalMode: DismissalMode {
        didSet {
            UserDefaults.standard.set(dismissalMode.rawValue, forKey: dismissalModeKey)
            NotificationCenter.default.post(name: .shortcutSettingsChanged, object: nil)
        }
    }

    /// Whether edge activation (mouse hover to trigger) is enabled.
    var edgeActivationEnabled: Bool {
        didSet { UserDefaults.standard.set(edgeActivationEnabled, forKey: edgeActivationEnabledKey) }
    }

    /// Whether to exclude screen corners from edge activation.
    var excludeCorners: Bool {
        didSet { UserDefaults.standard.set(excludeCorners, forKey: excludeCornersKey) }
    }

    /// Whether clicking outside the panel hides it.
    var hideOnClickOutside: Bool {
        didSet { UserDefaults.standard.set(hideOnClickOutside, forKey: hideOnClickOutsideKey) }
    }

    /// When true, the panel ignores all auto-hide triggers (mouse exit, click-outside,
    /// Space change) and stays visible until explicitly dismissed via Escape or the
    /// global toggle shortcut. Useful when copy-pasting back and forth with another app.
    /// Session-only (resets each launch).
    var isPanelPinned: Bool {
        didSet {
            NotificationCenter.default.post(name: .panelPinStateChanged, object: nil)
        }
    }

    /// Whether swipe-right in header navigates back.
    var swipeToNavigateEnabled: Bool {
        didSet { UserDefaults.standard.set(swipeToNavigateEnabled, forKey: swipeToNavigateEnabledKey) }
    }

    /// Whether swipe left/right on editor navigates between notes.
    var editorSwipeToNavigateEnabled: Bool {
        didSet { UserDefaults.standard.set(editorSwipeToNavigateEnabled, forKey: editorSwipeToNavigateEnabledKey) }
    }

    /// Swipe sensitivity (0–1). Higher = smaller required swipe distance.
    var swipeGestureSensitivity: Double {
        didSet { UserDefaults.standard.set(swipeGestureSensitivity, forKey: swipeGestureSensitivityKey) }
    }

    /// Width of the side panel in points. 400 = default minimum.
    var panelWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(panelWidth), forKey: panelWidthKey) }
    }

    /// Panel show/hide animation style.
    var animationStyle: AnimationStyle {
        didSet { UserDefaults.standard.set(animationStyle.rawValue, forKey: animationStyleKey) }
    }

    // MARK: - Keys

    private let autoHideKey = "autoHideOnMouseExit"
    private let hideDelayKey = "hideDelay"
    private let activationDelayKey = "activationDelay"
    private let toggleDismissDelayKey = "toggleDismissDelay"
    private let edgeSideKey = "edgeSide"
    private let dismissalModeKey = "dismissalMode"
    private let edgeActivationEnabledKey = "edgeActivationEnabled"
    private let excludeCornersKey = "excludeCorners"
    private let hideOnClickOutsideKey = "hideOnClickOutside"
    private let swipeToNavigateEnabledKey = "swipeToNavigateEnabled"
    private let editorSwipeToNavigateEnabledKey = "editorSwipeToNavigateEnabled"
    private let swipeGestureSensitivityKey = "swipeGestureSensitivity"
    private let panelWidthKey = "panelWidth"
    private let animationStyleKey = "animationStyle"

    // MARK: - Init

    private init() {
        autoHideOnMouseExit = UserDefaults.standard.object(forKey: autoHideKey) as? Bool ?? true
        hideDelay = UserDefaults.standard.object(forKey: hideDelayKey) as? Double ?? 0.5
        activationDelay = UserDefaults.standard.object(forKey: activationDelayKey) as? Double ?? 0.0
        toggleDismissDelay = UserDefaults.standard.object(forKey: toggleDismissDelayKey) as? Double ?? 0.3

        if let raw = UserDefaults.standard.string(forKey: edgeSideKey),
           let side = EdgeSide(rawValue: raw)
        {
            edgeSide = side
        } else {
            edgeSide = .right
        }
        if let raw = UserDefaults.standard.string(forKey: dismissalModeKey),
           let mode = DismissalMode(rawValue: raw)
        {
            dismissalMode = mode
        } else {
            dismissalMode = .auto
        }
        edgeActivationEnabled = UserDefaults.standard.object(forKey: edgeActivationEnabledKey) as? Bool ?? true
        excludeCorners = UserDefaults.standard.object(forKey: excludeCornersKey) as? Bool ?? true
        hideOnClickOutside = UserDefaults.standard.object(forKey: hideOnClickOutsideKey) as? Bool ?? true
        isPanelPinned = false
        swipeToNavigateEnabled = UserDefaults.standard.object(forKey: swipeToNavigateEnabledKey) as? Bool ?? true
        editorSwipeToNavigateEnabled = UserDefaults.standard.object(forKey: editorSwipeToNavigateEnabledKey) as? Bool ?? true
        swipeGestureSensitivity = UserDefaults.standard.object(forKey: swipeGestureSensitivityKey) as? Double ?? 0.5

        if let raw = UserDefaults.standard.string(forKey: animationStyleKey),
           let style = AnimationStyle(rawValue: raw)
        {
            animationStyle = style
        } else {
            animationStyle = .slide
        }

        // Panel width (stored as Double since UserDefaults doesn't have CGFloat)
        let savedWidth = UserDefaults.standard.object(forKey: panelWidthKey) as? Double
        panelWidth = savedWidth.map { CGFloat($0) } ?? 400
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let panelPinStateChanged = Notification.Name("panelPinStateChanged")
}
