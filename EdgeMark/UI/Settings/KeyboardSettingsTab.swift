import SwiftUI

struct KeyboardSettingsTab: View {
    @Environment(L10n.self) var l10n

    /// Global shortcut
    @State private var toggleShortcut: KeyboardShortcut?

    // Local configurable shortcuts
    @State private var newNoteShortcut: KeyboardShortcut?
    @State private var newFolderShortcut: KeyboardShortcut?
    @State private var searchShortcut: KeyboardShortcut?
    @State private var pinShortcut: KeyboardShortcut?
    @State private var previousNoteShortcut: KeyboardShortcut?
    @State private var nextNoteShortcut: KeyboardShortcut?

    init() {
        let s = ShortcutSettings.shared
        _toggleShortcut = State(initialValue: s.togglePanelShortcut)
        _newNoteShortcut = State(initialValue: s.newNoteShortcut)
        _newFolderShortcut = State(initialValue: s.newFolderShortcut)
        _searchShortcut = State(initialValue: s.searchShortcut)
        _pinShortcut = State(initialValue: s.pinShortcut)
        _previousNoteShortcut = State(initialValue: s.previousNoteShortcut)
        _nextNoteShortcut = State(initialValue: s.nextNoteShortcut)
    }

    var body: some View {
        Form {
            Section {
                Text(l10n["settings.keyboard.globalDescription"])
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(l10n["settings.keyboard.togglePanel"])
                    Spacer()
                    ShortcutRecorderView(shortcut: $toggleShortcut)
                        .frame(width: 180, height: 32)
                }
                .onChange(of: toggleShortcut) { _, v in
                    ShortcutSettings.shared.togglePanelShortcut = v
                }
            } header: {
                Label(l10n["settings.keyboard.globalShortcuts"], systemImage: "globe")
            }

            Section {
                editableRow(
                    ownKey: "settings.keyboard.newNote",
                    label: l10n["settings.keyboard.newNote"],
                    shortcut: $newNoteShortcut,
                    defaultValue: ShortcutSettings.defaultNewNote,
                    apply: { ShortcutSettings.shared.newNoteShortcut = $0 },
                )
                editableRow(
                    ownKey: "settings.keyboard.newFolder",
                    label: l10n["settings.keyboard.newFolder"],
                    shortcut: $newFolderShortcut,
                    defaultValue: ShortcutSettings.defaultNewFolder,
                    apply: { ShortcutSettings.shared.newFolderShortcut = $0 },
                )
                editableRow(
                    ownKey: "settings.keyboard.search",
                    label: l10n["settings.keyboard.search"],
                    shortcut: $searchShortcut,
                    defaultValue: ShortcutSettings.defaultSearch,
                    apply: { ShortcutSettings.shared.searchShortcut = $0 },
                )
                editableRow(
                    ownKey: "settings.keyboard.pinPanel",
                    label: l10n["settings.keyboard.pinPanel"],
                    shortcut: $pinShortcut,
                    defaultValue: ShortcutSettings.defaultPin,
                    apply: { ShortcutSettings.shared.pinShortcut = $0 },
                )
                localShortcutRow("Escape", l10n["settings.keyboard.hidePanel"])
                editableRow(
                    ownKey: "settings.keyboard.previousNote",
                    label: l10n["settings.keyboard.previousNote"],
                    shortcut: $previousNoteShortcut,
                    defaultValue: ShortcutSettings.defaultPreviousNote,
                    apply: { ShortcutSettings.shared.previousNoteShortcut = $0 },
                )
                editableRow(
                    ownKey: "settings.keyboard.nextNote",
                    label: l10n["settings.keyboard.nextNote"],
                    shortcut: $nextNoteShortcut,
                    defaultValue: ShortcutSettings.defaultNextNote,
                    apply: { ShortcutSettings.shared.nextNoteShortcut = $0 },
                )
            } header: {
                Label(l10n["settings.keyboard.localShortcuts"], systemImage: "keyboard")
            }

            Section {
                localShortcutRow("\u{2318}Z", l10n["settings.keyboard.undo"])
                localShortcutRow("\u{21E7}\u{2318}Z", l10n["settings.keyboard.redo"])
                localShortcutRow("\u{2318}B", l10n["settings.keyboard.bold"])
                localShortcutRow("\u{2318}I", l10n["settings.keyboard.italic"])
                localShortcutRow("\u{2318}E", l10n["settings.keyboard.inlineCode"])
                localShortcutRow("\u{2318}K", l10n["settings.keyboard.link"])
                localShortcutRow("\u{21E7}\u{2318}X", l10n["settings.keyboard.strikethrough"])
                localShortcutRow("/ (at line start)", l10n["settings.keyboard.slashCommand"])
                localShortcutRow("\u{2318} Click", l10n["settings.keyboard.openLink"])
            } header: {
                Label(l10n["settings.keyboard.formatting"], systemImage: "textformat")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Editable row

    @ViewBuilder
    private func editableRow(
        ownKey: String,
        label: String,
        shortcut: Binding<KeyboardShortcut?>,
        defaultValue: KeyboardShortcut,
        apply: @escaping (KeyboardShortcut?) -> Void,
    ) -> some View {
        let conflictKey = shortcut.wrappedValue.flatMap {
            ShortcutSettings.shared.conflictingKey(for: $0, excluding: ownKey)
        }

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let conflictKey {
                    Text("⚠ \(l10n["settings.keyboard.conflictsWith"]): \(l10n[conflictKey])")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            if shortcut.wrappedValue != defaultValue {
                Button(l10n["settings.keyboard.reset"]) {
                    shortcut.wrappedValue = defaultValue
                    // .onChange on the ShortcutRecorderView handles apply()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
            }
            ShortcutRecorderView(shortcut: shortcut)
                .frame(width: 140, height: 32)
                .onChange(of: shortcut.wrappedValue) { _, v in apply(v) }
        }
    }

    // MARK: - Display-only row (non-customizable)

    private func localShortcutRow(_ keys: String, _ description: String) -> some View {
        HStack {
            Text(description)
                .foregroundStyle(.secondary)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
        }
    }
}
