import SwiftUI

/// Shared footer bar with sort (left) and settings (right) menus.
/// Pinned at the bottom of the content card on home and folder list screens.
struct ContentFooterBar: View {
    @Environment(AppSettings.self) var settings

    var body: some View {
        HStack {
            sortMenu
            Spacer()
            settingsMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Sort Menu

    private var sortMenu: some View {
        Menu {
            ForEach(AppSettings.SortBy.allCases, id: \.self) { option in
                Button {
                    settings.sortBy = option
                } label: {
                    HStack {
                        Text(option.rawValue)
                        if settings.sortBy == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button {
                settings.sortAscending.toggle()
            } label: {
                HStack {
                    Text(settings.sortAscending ? "Ascending" : "Descending")
                    Image(systemName: settings.sortAscending ? "arrow.up" : "arrow.down")
                }
            }
        } label: {
            FooterIconLabel(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort")
    }

    // MARK: - Settings Menu

    private var settingsMenu: some View {
        Menu {
            Button("Settings\u{2026}") {}
                .disabled(true)

            Button("Check for Updates\u{2026}") {}
                .disabled(true)

            Divider()

            Button("Quit EdgeMark") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            FooterIconLabel(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings")
    }
}

// MARK: - Footer Icon Label

/// Small icon label for footer menu buttons with hover effect.
private struct FooterIconLabel: View {
    let systemName: String

    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(width: 24, height: 24)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.primary.opacity(isHovered ? 0.1 : 0))
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}
