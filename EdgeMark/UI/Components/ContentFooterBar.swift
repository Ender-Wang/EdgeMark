import Cocoa
import SwiftUI

/// Shared footer bar with sort (left) and settings (right) menus.
/// Pinned at the bottom of the shared content surface on home and folder list screens.
struct ContentFooterBar: View {
    @Environment(AppSettings.self) var settings
    @Environment(NoteStore.self) var noteStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let l10n = L10n.shared
        HStack {
            HeaderActionMenu(
                systemName: "arrow.up.arrow.down",
                help: l10n["sort.help"],
                arrowEdge: .bottom,
            ) { dismiss in
                sortActions(dismiss: dismiss)
            }
            Spacer()
            HeaderActionMenu(
                systemName: "gearshape",
                help: l10n["menu.settings"],
                arrowEdge: .bottom,
            ) { dismiss in
                settingsActions(dismiss: dismiss)
            }
        }
        .padding([.horizontal, .bottom], 16)
        .padding(.top, 6)
    }

    // MARK: - Sort Actions

    private func sortActions(dismiss: @escaping () -> Void) -> some View {
        let l10n = L10n.shared
        return VStack(spacing: 2) {
            ForEach(AppSettings.SortBy.allCases, id: \.self) { option in
                HeaderActionButton(
                    title: option.displayName(l10n),
                    systemName: sortIcon(for: option),
                    isSelected: settings.sortBy == option,
                ) {
                    dismiss()
                    settings.sortBy = option
                }
            }

            Divider()
                .padding(.vertical, 2)

            HeaderActionButton(
                title: settings.sortAscending ? l10n["sort.ascending"] : l10n["sort.descending"],
                systemName: settings.sortAscending ? "arrow.up" : "arrow.down",
            ) {
                dismiss()
                settings.sortAscending.toggle()
            }
        }
    }

    private func sortIcon(for option: AppSettings.SortBy) -> String {
        switch option {
        case .name: "textformat"
        case .dateModified: "clock"
        case .dateCreated: "calendar"
        }
    }

    // MARK: - Settings Actions

    private func settingsActions(dismiss: @escaping () -> Void) -> some View {
        let l10n = L10n.shared
        return VStack(spacing: 2) {
            HeaderActionButton(title: l10n["common.trash"], systemName: "trash") {
                dismiss()
                noteStore.openTrash()
            }

            Divider()
                .padding(.vertical, 2)

            HeaderActionButton(title: l10n["menu.settings"], systemName: "gearshape") {
                dismiss()
                openSettings()
            }
            HeaderActionButton(
                title: l10n["menu.checkUpdates"],
                systemName: "arrow.triangle.2.circlepath",
            ) {
                dismiss()
                AppDelegate.shared?.checkForUpdates()
            }

            Divider()
                .padding(.vertical, 2)

            HeaderActionButton(title: l10n["menu.quit"], systemName: "power") {
                dismiss()
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
