import SwiftUI

struct SettingsView: View {
    @Environment(L10n.self) var l10n

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label(l10n["settings.tab.general"], systemImage: "gearshape")
                }

            BehaviorSettingsTab()
                .tabItem {
                    Label(l10n["settings.tab.behavior"], systemImage: "macwindow.on.rectangle")
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
        .background(FixedWindowTitle(title: l10n["settings.windowTitle"]))
        .frame(width: 520, height: 420)
    }
}

// MARK: - Window title override

/// Forces a fixed window title via KVO, overriding the TabView's default
/// behavior of changing the title to match the selected tab name.
private struct FixedWindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context _: Context) -> TitleFixView {
        TitleFixView(fixedTitle: title)
    }

    func updateNSView(_ nsView: TitleFixView, context _: Context) {
        nsView.fixedTitle = title
        nsView.applyTitle()
    }

    final class TitleFixView: NSView {
        var fixedTitle: String
        private var observation: NSKeyValueObservation?

        init(fixedTitle: String) {
            self.fixedTitle = fixedTitle
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = window?.observe(\.title, options: [.new]) { [weak self] window, _ in
                guard let self, window.title != self.fixedTitle else { return }
                window.title = fixedTitle
            }
            applyTitle()
        }

        func applyTitle() {
            guard let window, window.title != fixedTitle else { return }
            window.title = fixedTitle
        }
    }
}
