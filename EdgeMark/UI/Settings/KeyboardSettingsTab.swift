import SwiftUI

struct KeyboardSettingsTab: View {
    @Environment(L10n.self) var l10n
    @State private var toggleShortcut: KeyboardShortcut?

    init() {
        _toggleShortcut = State(initialValue: ShortcutSettings.shared.togglePanelShortcut)
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
                .onChange(of: toggleShortcut) { _, newValue in
                    ShortcutSettings.shared.togglePanelShortcut = newValue
                }
            } header: {
                Label(l10n["settings.keyboard.globalShortcuts"], systemImage: "globe")
            }

            Section {
                localShortcutRow("\u{2318}N", l10n["settings.keyboard.newNote"])
                localShortcutRow("\u{21E7}\u{2318}N", l10n["settings.keyboard.newFolder"])
                localShortcutRow("\u{2318}F", l10n["settings.keyboard.search"])
                localShortcutRow("Escape", l10n["settings.keyboard.hidePanel"])
                localShortcutRow("/ (at line start)", l10n["settings.keyboard.slashCommand"])
                localShortcutRow("\u{2318}Z", l10n["settings.keyboard.undo"])
                localShortcutRow("\u{21E7}\u{2318}Z", l10n["settings.keyboard.redo"])
                localShortcutRow("\u{2318}\u{2190}", l10n["settings.keyboard.previousNote"])
                localShortcutRow("\u{2318}\u{2192}", l10n["settings.keyboard.nextNote"])
            } header: {
                Label(l10n["settings.keyboard.localShortcuts"], systemImage: "keyboard")
            }
        }
        .formStyle(.grouped)
    }

    private func localShortcutRow(_ keys: String, _ description: String) -> some View {
        HStack {
            Text(description)
                .foregroundStyle(.secondary)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary),
                )
        }
    }
}
