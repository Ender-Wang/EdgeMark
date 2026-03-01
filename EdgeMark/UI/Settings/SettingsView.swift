import SwiftUI

struct SettingsView: View {
    @Environment(L10n.self) var l10n

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label(l10n["settings.tab.general"], systemImage: "gearshape")
                }

            KeyboardSettingsTab()
                .tabItem {
                    Label(l10n["settings.tab.keyboard"], systemImage: "keyboard")
                }

            AboutSettingsTab()
                .tabItem {
                    Label(l10n["settings.tab.about"], systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 420)
    }
}
