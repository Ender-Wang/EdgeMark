import SwiftUI

struct GeneralSettingsTab: View {
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
    }

    var body: some View {
        Form {
            Section("Panel position") {
                Picker("Edge", selection: $edgeSide) {
                    Text("Left").tag(EdgeSide.left)
                    Text("Right").tag(EdgeSide.right)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .onChange(of: edgeSide) { _, newValue in
                    ShortcutSettings.shared.edgeSide = newValue
                }
            }

            Section("Edge activation") {
                Toggle("Enable edge activation", isOn: $edgeActivationEnabled)
                    .onChange(of: edgeActivationEnabled) { _, v in
                        ShortcutSettings.shared.edgeActivationEnabled = v
                    }

                if edgeActivationEnabled {
                    HStack {
                        Text("Activation delay")
                        Slider(value: $activationDelay, in: 0 ... 1, step: 0.1)
                            .onChange(of: activationDelay) { _, v in
                                ShortcutSettings.shared.activationDelay = v
                            }
                        Text(String(format: "%.1fs", activationDelay))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }

                    Toggle("Exclude screen corners", isOn: $excludeCorners)
                        .onChange(of: excludeCorners) { _, v in
                            ShortcutSettings.shared.excludeCorners = v
                        }
                }
            }

            Section("Auto-hide") {
                Toggle("Auto-hide when mouse exits", isOn: $autoHideOnMouseExit)
                    .onChange(of: autoHideOnMouseExit) { _, v in
                        ShortcutSettings.shared.autoHideOnMouseExit = v
                    }

                if autoHideOnMouseExit {
                    HStack {
                        Text("Hide delay")
                        Slider(value: $hideDelay, in: 0 ... 3, step: 0.1)
                            .onChange(of: hideDelay) { _, v in
                                ShortcutSettings.shared.hideDelay = v
                            }
                        Text(String(format: "%.1fs", hideDelay))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                Toggle("Hide when clicking outside", isOn: $hideOnClickOutside)
                    .onChange(of: hideOnClickOutside) { _, v in
                        ShortcutSettings.shared.hideOnClickOutside = v
                    }
            }

            Section("System") {
                Toggle("Check for updates automatically", isOn: $autoCheckUpdates)
                    .onChange(of: autoCheckUpdates) { _, v in
                        ShortcutSettings.shared.autoCheckUpdates = v
                    }

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        ShortcutSettings.shared.launchAtLogin = v
                    }
            }

            Section("Notes storage") {
                LabeledContent("Location") {
                    Text(storagePath)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Show in Finder") {
                        NSWorkspace.shared.open(ShortcutSettings.shared.resolvedStorageDirectory)
                    }
                    Spacer()
                    Button("Change Notes Folder\u{2026}") {
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
