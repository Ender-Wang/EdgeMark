import SwiftUI

struct GeneralSettingsTab: View {
    @Environment(L10n.self) var l10n
    @Environment(AppSettings.self) var appSettings

    @State private var appearanceMode: AppearanceMode
    @State private var autoCheckUpdates: Bool
    @State private var launchAtLogin: Bool
    @State private var storagePath: String
    @State private var selectedLocale: String

    init() {
        let s = ShortcutSettings.shared
        _appearanceMode = State(initialValue: s.appearanceMode)
        _autoCheckUpdates = State(initialValue: s.autoCheckUpdates)
        _launchAtLogin = State(initialValue: s.launchAtLogin)
        _storagePath = State(initialValue: s.resolvedStorageDirectory.path(percentEncoded: false))
        _selectedLocale = State(initialValue: L10n.shared.locale)
    }

    var body: some View {
        @Bindable var settings = appSettings
        Form {
            Section {
                Picker(l10n["settings.general.appearance"], selection: $appearanceMode) {
                    Text(l10n["settings.appearance.system"]).tag(AppearanceMode.system)
                    Text(l10n["settings.appearance.light"]).tag(AppearanceMode.light)
                    Text(l10n["settings.appearance.dark"]).tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
                .onChange(of: appearanceMode) { _, newValue in
                    ShortcutSettings.shared.appearanceMode = newValue
                }

                Picker(l10n["settings.general.panelTint"], selection: $settings.panelTint) {
                    ForEach(AppSettings.PanelTint.allCases, id: \.self) { tint in
                        Text(tint.displayName(l10n)).tag(tint)
                    }
                }
            } header: {
                Label(l10n["settings.general.appearance"], systemImage: "circle.lefthalf.filled")
            }

            Section {
                Picker(l10n["settings.general.language"], selection: $selectedLocale) {
                    Text(l10n["settings.language.system"]).tag("system")
                    Text(l10n["settings.language.en"]).tag("en")
                    Text(l10n["settings.language.zh"]).tag("zh-Hans")
                }
                .onChange(of: selectedLocale) { _, newValue in
                    L10n.shared.locale = newValue
                }
            } header: {
                Label(l10n["settings.general.language"], systemImage: "globe")
            }

            Section {
                Toggle(l10n["settings.general.autoCheckUpdates"], isOn: $autoCheckUpdates)
                    .onChange(of: autoCheckUpdates) { _, v in
                        ShortcutSettings.shared.autoCheckUpdates = v
                    }

                Toggle(l10n["settings.general.launchAtLogin"], isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        ShortcutSettings.shared.launchAtLogin = v
                    }
            } header: {
                Label(l10n["settings.general.system"], systemImage: "gearshape.2")
            }

            Section {
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
            } header: {
                Label(l10n["settings.general.storage"], systemImage: "folder")
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: .shortcutSettingsChanged)) { _ in
            storagePath = ShortcutSettings.shared.resolvedStorageDirectory.path(percentEncoded: false)
        }
    }
}
