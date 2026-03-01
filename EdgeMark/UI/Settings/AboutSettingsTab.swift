import SwiftUI

struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App icon + name + version
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)

                Text("EdgeMark")
                    .font(.title.bold())

                Text("Version \(appVersion) (Build \(buildNumber))")
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.horizontal, 40)

            // Links
            VStack(spacing: 10) {
                Link(destination: URL(string: "https://github.com/Ender-Wang/EdgeMark")!) {
                    Label("View on GitHub", systemImage: "arrow.up.right.square")
                }

                Link(destination: URL(string: "https://github.com/Ender-Wang/EdgeMark/issues/new?template=bug_report.md")!) {
                    Label("Report a Bug", systemImage: "ladybug")
                }

                Link(destination: URL(string: "https://github.com/Ender-Wang/EdgeMark/issues/new?template=feature_request.md")!) {
                    Label("Request a Feature", systemImage: "lightbulb")
                }
            }

            Spacer()

            // Copyright
            Text("\u{00A9} \(currentYear) Ender Wang. Licensed under GPLv3.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - App Info

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    private var currentYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }
}
