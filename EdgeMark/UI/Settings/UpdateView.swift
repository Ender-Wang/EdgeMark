import SwiftUI

struct UpdateView: View {
    @Environment(UpdateState.self) private var updateState

    var body: some View {
        VStack(spacing: 0) {
            switch updateState.status {
            case let .available(release):
                availableContent(release: release)
            case let .downloading(progress):
                downloadingContent(progress: progress)
            case let .readyToInstall(release, _):
                readyContent(release: release)
            case .installing:
                installingContent
            case let .error(error):
                errorContent(error: error)
            default:
                EmptyView()
            }
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Update Available

    private func availableContent(release: GitHubRelease) -> some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("EdgeMark \u{2014} Update Available")
                        .font(.headline)
                    HStack(spacing: 0) {
                        if let date = release.publishedDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                            Text(" \u{00B7} ")
                                .foregroundStyle(.tertiary)
                        }
                        Text("v\(release.version)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    HStack(spacing: 0) {
                        Text("v\(currentVersion) (build \(buildNumber))")
                        Text(" \u{00B7} ")
                        Text("Current")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 20)

            Divider()

            // Release notes
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Release Notes")
                        .font(.headline)

                    releaseNotesBody(release.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .frame(maxHeight: 200)

            Divider()

            // Footer
            HStack {
                Button("View on GitHub") {
                    if let url = URL(string: release.htmlURL) {
                        NSWorkspace.shared.open(url)
                    }
                }

                Spacer()

                Button("Later") {
                    closeWindow()
                }
                .keyboardShortcut(.cancelAction)

                Button("Download & Install") {
                    updateState.downloadUpdate(release)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Downloading

    private func downloadingContent(progress: UpdateProgress) -> some View {
        VStack(spacing: 16) {
            Text("Downloading Update\u{2026}")
                .font(.headline)
                .padding(.top, 20)

            ProgressView(value: progress.percentage)
                .padding(.horizontal)

            HStack {
                Text(formatBytes(progress.bytesDownloaded))
                Text("/")
                Text(formatBytes(progress.totalBytes))
                Text("\u{2014}")
                Text(formatSpeed(progress.speedBytesPerSecond))
                if progress.speedBytesPerSecond > 0, progress.etaSeconds < 3600 {
                    Text("\u{2014}")
                    Text(formatETA(progress.etaSeconds))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("\(Int(progress.percentage * 100))%")
                .font(.title2.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("Cancel") {
                updateState.cancelDownload()
                closeWindow()
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Ready to Install

    private func readyContent(release _: GitHubRelease) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
                .padding(.top, 20)

            Text("Download Complete")
                .font(.headline)

            Text("EdgeMark will quit and restart to complete the update.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack {
                Button("Later") {
                    closeWindow()
                }

                Button("Install & Restart") {
                    Task {
                        await updateState.installUpdate()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Installing

    private var installingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .padding(.top, 20)

            Text("Installing\u{2026}")
                .font(.headline)

            Text("EdgeMark will restart automatically.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Error

    private func errorContent(error: UpdateError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)
                .padding(.top, 20)

            Text("Update Failed")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Dismiss") {
                updateState.status = .idle
                closeWindow()
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Window

    private func closeWindow() {
        NSApp.keyWindow?.close()
    }

    // MARK: - Markdown Rendering

    private func releaseNotesBody(_ markdown: String) -> some View {
        let lines = markdown.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    Spacer().frame(height: 4)
                } else if trimmed.hasPrefix("## ") {
                    Text(String(trimmed.dropFirst(3)))
                        .font(.body.bold())
                        .padding(.top, 4)
                } else if trimmed.hasPrefix("# ") {
                    Text(String(trimmed.dropFirst(2)))
                        .font(.title3.bold())
                        .padding(.top, 4)
                } else if trimmed.hasPrefix("- ") {
                    HStack(alignment: .top, spacing: 6) {
                        Text("\u{2022}")
                            .font(.body)
                        Text(inlineMarkdown(String(trimmed.dropFirst(2))))
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(.leading, 4)
                } else {
                    Text(inlineMarkdown(trimmed))
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    // MARK: - Formatting

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }

    private func formatETA(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s < 60 {
            return "\(s)s remaining"
        }
        return "\(s / 60)m remaining"
    }

    // MARK: - App Info

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
