import SwiftUI

struct BehaviorSettingsTab: View {
    @Environment(L10n.self) var l10n

    @State private var edgeSide: EdgeSide
    @State private var edgeActivationEnabled: Bool
    @State private var activationDelay: Double
    @State private var excludeCorners: Bool
    @State private var autoHideOnMouseExit: Bool
    @State private var hideDelay: Double
    @State private var hideOnClickOutside: Bool

    init() {
        let s = ShortcutSettings.shared
        _edgeSide = State(initialValue: s.edgeSide)
        _edgeActivationEnabled = State(initialValue: s.edgeActivationEnabled)
        _activationDelay = State(initialValue: s.activationDelay)
        _excludeCorners = State(initialValue: s.excludeCorners)
        _autoHideOnMouseExit = State(initialValue: s.autoHideOnMouseExit)
        _hideDelay = State(initialValue: s.hideDelay)
        _hideOnClickOutside = State(initialValue: s.hideOnClickOutside)
    }

    var body: some View {
        Form {
            Section {
                Picker(l10n["settings.general.edge"], selection: $edgeSide) {
                    Text(l10n["settings.general.left"]).tag(EdgeSide.left)
                    Text(l10n["settings.general.right"]).tag(EdgeSide.right)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .onChange(of: edgeSide) { _, newValue in
                    ShortcutSettings.shared.edgeSide = newValue
                }
            } header: {
                Label(l10n["settings.general.panelPosition"], systemImage: "sidebar.right")
            }

            Section {
                Toggle(l10n["settings.general.enableEdgeActivation"], isOn: $edgeActivationEnabled)
                    .onChange(of: edgeActivationEnabled) { _, v in
                        ShortcutSettings.shared.edgeActivationEnabled = v
                    }

                if edgeActivationEnabled {
                    HStack {
                        Text(l10n["settings.general.activationDelay"])
                        Slider(value: $activationDelay, in: 0 ... 1, step: 0.1)
                            .onChange(of: activationDelay) { _, v in
                                ShortcutSettings.shared.activationDelay = v
                            }
                        Text(String(format: "%.1fs", activationDelay))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }

                    Toggle(l10n["settings.general.excludeCorners"], isOn: $excludeCorners)
                        .onChange(of: excludeCorners) { _, v in
                            ShortcutSettings.shared.excludeCorners = v
                        }
                }
            } header: {
                Label(l10n["settings.general.edgeActivation"], systemImage: "cursorarrow.motionlines")
            }

            Section {
                Toggle(l10n["settings.general.autoHideOnExit"], isOn: $autoHideOnMouseExit)
                    .onChange(of: autoHideOnMouseExit) { _, v in
                        ShortcutSettings.shared.autoHideOnMouseExit = v
                    }

                if autoHideOnMouseExit {
                    HStack {
                        Text(l10n["settings.general.hideDelay"])
                        Slider(value: $hideDelay, in: 0 ... 3, step: 0.1)
                            .onChange(of: hideDelay) { _, v in
                                ShortcutSettings.shared.hideDelay = v
                            }
                        Text(String(format: "%.1fs", hideDelay))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                Toggle(l10n["settings.general.hideOnClickOutside"], isOn: $hideOnClickOutside)
                    .onChange(of: hideOnClickOutside) { _, v in
                        ShortcutSettings.shared.hideOnClickOutside = v
                    }
            } header: {
                Label(l10n["settings.general.autoHide"], systemImage: "eye.slash")
            }
        }
        .formStyle(.grouped)
        .animation(.easeInOut(duration: 0.2), value: edgeActivationEnabled)
        .animation(.easeInOut(duration: 0.2), value: autoHideOnMouseExit)
    }
}
