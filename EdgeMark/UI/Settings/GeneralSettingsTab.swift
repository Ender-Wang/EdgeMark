import SwiftUI

struct GeneralSettingsTab: View {
    @Environment(L10n.self) var l10n

    @State private var edgeSide: EdgeSide
    @State private var edgeActivationEnabled: Bool
    @State private var activationDelay: Double
    @State private var excludeCorners: Bool
    @State private var autoHideOnMouseExit: Bool
    @State private var hideDelay: Double
    @State private var hideOnClickOutside: Bool
    @State private var autoCheckUpdates: Bool
    @State private var launchAtLogin: Bool
    @State private var storagePath: String
    @State private var selectedLocale: String

    init() {
        let s = ShortcutSettings.shared
        _edgeSide = State(initialValue: s.edgeSide)
        _edgeActivationEnabled = State(initialValue: s.edgeActivationEnabled)
        _activationDelay = State(initialValue: s.activationDelay)
        _excludeCorners = State(initialValue: s.excludeCorners)
        _autoHideOnMouseExit = State(initialValue: s.autoHideOnMouseExit)
        _hideDelay = State(initialValue: s.hideDelay)
        _hideOnClickOutside = State(initialValue: s.hideOnClickOutside)
        _autoCheckUpdates = State(initialValue: s.autoCheckUpdates)
        _launchAtLogin = State(initialValue: s.launchAtLogin)
        _storagePath = State(initialValue: s.resolvedStorageDirectory.path(percentEncoded: false))
        _selectedLocale = State(initialValue: L10n.shared.locale)
    }

    var body: some View {
        Form {
            Section(l10n["settings.general.panelPosition"]) {
                Picker(l10n["settings.general.edge"], selection: $edgeSide) {
                    Text(l10n["settings.general.left"]).tag(EdgeSide.left)
                    Text(l10n["settings.general.right"]).tag(EdgeSide.right)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .onChange(of: edgeSide) { _, newValue in
                    ShortcutSettings.shared.edgeSide = newValue
                }
            }

            Section(l10n["settings.general.edgeActivation"]) {
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
            }

            Section(l10n["settings.general.autoHide"]) {
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
            }

            Section(l10n["settings.general.system"]) {
                Toggle(l10n["settings.general.autoCheckUpdates"], isOn: $autoCheckUpdates)
                    .onChange(of: autoCheckUpdates) { _, v in
                        ShortcutSettings.shared.autoCheckUpdates = v
                    }

                Toggle(l10n["settings.general.launchAtLogin"], isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        ShortcutSettings.shared.launchAtLogin = v
                    }
            }

            Section(l10n["settings.general.language"]) {
                Picker(l10n["settings.general.language"], selection: $selectedLocale) {
                    Text(l10n["settings.language.system"]).tag("system")
                    Text(l10n["settings.language.en"]).tag("en")
                    Text(l10n["settings.language.zh"]).tag("zh-Hans")
                }
                .fixedSize()
                .onChange(of: selectedLocale) { _, newValue in
                    L10n.shared.locale = newValue
                }
            }

            Section(l10n["settings.general.storage"]) {
                LabeledContent(l10n["settings.general.location"]) {
                    Text(storagePath)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Button(l10n["settings.general.showInFinder"]) {
                        NSWorkspace.shared.open(ShortcutSettings.shared.resolvedStorageDirectory)
                    }
                    Spacer()
                    Button(l10n["settings.general.changeFolder"]) {
                        NSApp.sendAction(#selector(AppDelegate.changeNotesFolder), to: nil, from: nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .animation(.easeInOut(duration: 0.2), value: edgeActivationEnabled)
        .animation(.easeInOut(duration: 0.2), value: autoHideOnMouseExit)
        .onReceive(NotificationCenter.default.publisher(for: .shortcutSettingsChanged)) { _ in
            storagePath = ShortcutSettings.shared.resolvedStorageDirectory.path(percentEncoded: false)
        }
    }
}
