import OSLog
import SwiftUI

struct GeneralSettingsTab: View {
    @Environment(L10n.self) var l10n
    @Environment(AppSettings.self) var appSettings

    @State private var appearanceMode: AppSettings.AppearanceMode
    @State private var autoCheckUpdates: Bool
    @State private var launchAtLogin: Bool
    @State private var selectedLocale: String
    // Multiple storage locations (#55). Mirrored from StorageSettings (a plain class,
    // not @Observable) and refreshed on .storageRootChanged.
    @State private var roots: [StorageRoot]
    @State private var activeRootID: String?
    @State private var askOnLaunch: Bool
    @State private var removalBlockedMessage: String?
    @State private var hoveredCheckboxPreset: AppSettings.TaskCheckboxPreset?

    init() {
        _appearanceMode = State(initialValue: AppSettings.shared.appearanceMode)
        _autoCheckUpdates = State(initialValue: AppSettings.shared.autoCheckUpdates)
        _launchAtLogin = State(initialValue: AppSettings.shared.launchAtLogin)
        _roots = State(initialValue: StorageSettings.shared.storageRoots)
        _activeRootID = State(initialValue: StorageSettings.shared.activeStorageRoot?.id)
        _askOnLaunch = State(initialValue: StorageSettings.shared.askOnLaunch)
        _selectedLocale = State(initialValue: L10n.shared.locale)
    }

    private var currentFontDescription: String {
        guard let postscript = appSettings.editorFontName,
              let f = NSFont(name: postscript, size: 13)
        else {
            return l10n["settings.editor.systemFont"]
        }
        // Strip the leading dot AppKit uses for internal/system family names
        // (e.g. ".AppleSystemUIFont", ".SF NS"), which shouldn't surface in UI.
        let name = f.familyName ?? f.fontName
        return name.hasPrefix(".") ? l10n["settings.editor.systemFont"] : name
    }

    var body: some View {
        @Bindable var settings = appSettings
        Form {
            Section {
                Picker(l10n["settings.general.appearance"], selection: $appearanceMode) {
                    Text(l10n["settings.appearance.system"]).tag(AppSettings.AppearanceMode.system)
                    Text(l10n["settings.appearance.light"]).tag(AppSettings.AppearanceMode.light)
                    Text(l10n["settings.appearance.dark"]).tag(AppSettings.AppearanceMode.dark)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
                .onChange(of: appearanceMode) { _, newValue in
                    AppSettings.shared.appearanceMode = newValue
                }

                Picker(l10n["settings.general.panelStyle"], selection: $settings.panelStyle) {
                    ForEach(AppSettings.PanelStyle.allCases, id: \.self) { style in
                        Text(style.displayName(l10n)).tag(style)
                    }
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
                LabeledContent(l10n["settings.editor.font"]) {
                    HStack(spacing: 8) {
                        Text(currentFontDescription)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        FontPickerButton(title: l10n["settings.editor.chooseFont"])
                            .fixedSize()
                        if settings.editorFontName != nil {
                            Button(l10n["settings.editor.resetFont"]) {
                                settings.editorFontName = nil
                            }
                        }
                    }
                }

                LabeledContent(l10n["settings.editor.fontSize"]) {
                    HStack(spacing: 8) {
                        Text("\(Int(settings.editorFontSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Stepper(
                            "",
                            value: $settings.editorFontSize, in: 11 ... 28, step: 1,
                        )
                        .labelsHidden()
                        if settings.editorFontSize != 16 {
                            Button(l10n["settings.editor.resetFont"]) {
                                settings.editorFontSize = 16
                            }
                        }
                    }
                }

                LabeledContent(l10n["settings.editor.checkboxStyle"]) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(AppSettings.TaskCheckboxPreset.allCases, id: \.self) { preset in
                                let isSelected = settings.taskCheckboxPreset == preset
                                let isHovered = hoveredCheckboxPreset == preset
                                Button {
                                    settings.taskCheckboxPreset = preset
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: preset.uncheckedSymbolName)
                                        Image(systemName: preset.checkedSymbolName)
                                    }
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? Color.accentColor : (isHovered ? .primary : .secondary))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(.primary.opacity(isSelected ? 0.12 : (isHovered ? 0.08 : 0))),
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.accentColor, lineWidth: isSelected ? 1.5 : 0),
                                    )
                                }
                                .buttonStyle(.plain)
                                .onHover { hoveredCheckboxPreset = $0 ? preset : nil }
                                .help(l10n["settings.editor.checkboxStyle.\(preset.rawValue)"])
                            }
                        }
                        .animation(.easeInOut(duration: 0.15), value: hoveredCheckboxPreset)
                    }
                }

                Toggle(l10n["settings.editor.spellChecking"], isOn: $settings.spellCheckingEnabled)
                Toggle(l10n["settings.editor.grammarChecking"], isOn: $settings.grammarCheckingEnabled)
                Toggle(l10n["settings.editor.autocorrect"], isOn: $settings.automaticSpellingCorrectionEnabled)
                Toggle(l10n["settings.editor.hoverPeek"], isOn: $settings.hoverPeekEnabled)
                Picker(l10n["settings.editor.hoverDelay"], selection: $settings.hoverPeekDelay) {
                    ForEach(AppSettings.HoverPeekDelay.allCases, id: \.self) { delay in
                        Text(delay.displayName(l10n)).tag(delay)
                    }
                }
                .disabled(!settings.hoverPeekEnabled)
                Toggle(l10n["settings.editor.spacePreview"], isOn: $settings.spaceToPreviewEnabled)
            } header: {
                Label(l10n["settings.editor.section"], systemImage: "textformat")
            }

            Section {
                Picker(l10n["settings.general.language"], selection: $selectedLocale) {
                    Text(l10n["settings.language.system"]).tag("system")
                    ForEach(L10n.availableLocales, id: \.code) { locale in
                        Text(locale.displayName).tag(locale.code)
                    }
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
                        AppSettings.shared.autoCheckUpdates = v
                    }

                Toggle(l10n["settings.general.launchAtLogin"], isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in
                        AppSettings.shared.launchAtLogin = v
                    }
            } header: {
                Label(l10n["settings.general.system"], systemImage: "gearshape.2")
            }

            Section {
                ForEach(roots) { root in
                    storageRootRow(root)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(l10n["settings.general.askOnLaunch"], isOn: $askOnLaunch)
                        .disabled(roots.count < 2)
                        .onChange(of: askOnLaunch) { _, v in
                            StorageSettings.shared.askOnLaunch = v
                        }
                    Text(l10n["settings.general.askOnLaunchHint"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Label(l10n["settings.general.storage"], systemImage: "folder")
                    Spacer()
                    Button {
                        addLocation()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help(l10n["settings.general.addLocation"])
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: .storageRootChanged)) { _ in
            roots = StorageSettings.shared.storageRoots
            activeRootID = StorageSettings.shared.activeStorageRoot?.id
            askOnLaunch = StorageSettings.shared.askOnLaunch
        }
        .alert("Cannot remove", isPresented: .constant(removalBlockedMessage != nil)) {
            Button(l10n["common.ok"]) { removalBlockedMessage = nil }
        } message: {
            Text(removalBlockedMessage ?? "")
        }
    }

    @ViewBuilder
    private func storageRootRow(_ root: StorageRoot) -> some View {
        let isActive = activeRootID == root.id
        HStack(alignment: .center, spacing: 10) {
            Button {
                AppDelegate.shared?.switchRoot(to: root, temporary: false)
            } label: {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .disabled(isActive)
            .help(isActive ? "" : l10n["settings.general.setAsDefault"])

            VStack(alignment: .leading, spacing: 2) {
                TextField(
                    l10n["common.rename"],
                    text: labelBinding(forID: root.id),
                )
                .textFieldStyle(.plain)
                .font(.body)
                .labelsHidden()
                Text(root.url.path(percentEncoded: false))
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(root.url)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(l10n["settings.general.showInFinder"])
            Button {
                NSApp.sendAction(#selector(AppDelegate.changeNotesFolder), to: nil, from: nil)
            } label: {
                Image(systemName: "arrow.right.arrow.left")
            }
            .buttonStyle(.borderless)
            .help(l10n["settings.general.changeFolder"])
            Button(role: .destructive) {
                removeRoot(root)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(l10n["settings.general.removeLocation"])
        }
        .padding(.vertical, 2)
    }

    private func labelBinding(forID id: String) -> Binding<String> {
        Binding(
            get: {
                if let r = StorageSettings.shared.storageRoots.first(where: { $0.id == id }) {
                    return r.label ?? r.url.lastPathComponent
                }
                return ""
            },
            set: { newVal in
                var current = StorageSettings.shared.storageRoots
                if let idx = current.firstIndex(where: { $0.id == id }) {
                    current[idx].label = newVal.isEmpty ? nil : newVal
                }
                StorageSettings.shared.storageRoots = current
                roots = current
            },
        )
    }

    private func addLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = l10n["settings.general.addLocationMessage"]
        panel.prompt = l10n["common.select"]
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            var current = StorageSettings.shared.storageRoots
            guard !current.contains(where: { $0.url == url }) else { return }
            do {
                try FileStorage.ensureRootStructure(at: url)
            } catch {
                let msg = error.localizedDescription
                Log.storage.error("[Settings] ensureRootStructure failed: \(msg)")
                return
            }
            current.append(StorageRoot(id: UUID().uuidString, url: url, label: nil))
            StorageSettings.shared.storageRoots = current
            roots = current
        }
    }

    private func removeRoot(_ root: StorageRoot) {
        var current = StorageSettings.shared.storageRoots
        guard current.count > 1 else {
            removalBlockedMessage = l10n["settings.general.cantRemoveLast"]
            return
        }
        let wasActive = StorageSettings.shared.activeRootID == root.id
            || StorageSettings.shared.sessionRootOverride?.id == root.id
        current.removeAll { $0.id == root.id }
        StorageSettings.shared.storageRoots = current
        roots = current
        if wasActive, let next = current.first {
            AppDelegate.shared?.switchRoot(to: next, temporary: false)
        }
    }
}
