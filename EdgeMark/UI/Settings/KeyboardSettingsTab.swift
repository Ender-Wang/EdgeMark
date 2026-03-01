import SwiftUI

struct KeyboardSettingsTab: View {
    @State private var toggleShortcut: KeyboardShortcut?

    init() {
        _toggleShortcut = State(initialValue: ShortcutSettings.shared.togglePanelShortcut)
    }

    var body: some View {
        Form {
            Section {
                Text("These keyboard shortcuts work system-wide, even when EdgeMark is in the background.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Toggle EdgeMark")
                    Spacer()
                    ShortcutRecorderView(shortcut: $toggleShortcut)
                        .frame(width: 180, height: 32)
                }
                .onChange(of: toggleShortcut) { _, newValue in
                    ShortcutSettings.shared.togglePanelShortcut = newValue
                }
            } header: {
                Text("Global shortcuts")
            }

            Section("Local shortcuts") {
                localShortcutRow("Escape", "Hide panel or go back")
                localShortcutRow("/ (at line start)", "Open slash command menu")
                localShortcutRow("\u{2318}Z", "Undo")
                localShortcutRow("\u{21E7}\u{2318}Z", "Redo")
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
