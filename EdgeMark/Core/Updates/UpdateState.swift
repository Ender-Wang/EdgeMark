import Foundation
import OSLog

/// Observable update state — drives UpdateView reactivity (matches Swifka's AppState pattern).
@Observable
final class UpdateState {
    var status: UpdateStatus = .idle

    let checker = UpdateChecker()
    private var downloadTask: Task<Void, Never>?

    // MARK: - Check

    enum Source {
        case launch
        case manual
        case settings
    }

    func check(source _: Source) async {
        status = .checking
        do {
            if let release = try await checker.checkForUpdate() {
                status = .available(release)
            } else {
                status = .upToDate
            }
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheckDate")
        } catch {
            if let updateError = error as? UpdateError {
                status = .error(updateError)
            } else {
                status = .error(.networkError(error.localizedDescription))
            }
        }
    }

    // MARK: - Download

    func downloadUpdate(_ release: GitHubRelease) {
        guard let asset = release.dmgAsset else {
            status = .error(.noAssetFound)
            return
        }

        // Immediate visual feedback
        status = .downloading(UpdateProgress(
            bytesDownloaded: 0,
            totalBytes: Int64(asset.size),
            speedBytesPerSecond: 0,
        ))

        downloadTask = Task { [weak self] in
            do {
                let dmgURL = try await UpdateDownloader.download(asset: asset) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.status = .downloading(progress)
                    }
                }

                // Verify checksum if available
                if let checksumAsset = release.checksumAsset {
                    Log.updates.info("[UpdateState] verifying checksum...")
                    guard let self else { return }
                    let expected = try await checker.fetchChecksum(from: checksumAsset)
                    let valid = try ChecksumVerifier.verify(dmgURL, expected: expected)
                    if !valid {
                        status = .error(.checksumMismatch)
                        return
                    }
                    Log.updates.info("[UpdateState] checksum verified")
                }

                await MainActor.run { [weak self] in
                    self?.status = .readyToInstall(release, dmgURL)
                }
            } catch {
                await MainActor.run { [weak self] in
                    if let updateError = error as? UpdateError {
                        if case .cancelled = updateError {
                            self?.status = .idle
                            return
                        }
                        self?.status = .error(updateError)
                    } else {
                        self?.status = .error(.networkError(error.localizedDescription))
                    }
                }
            }
        }
    }

    // MARK: - Install

    func installUpdate() async {
        guard case let .readyToInstall(_, dmgURL) = status else { return }
        status = .installing
        do {
            try await UpdateInstaller.install(downloadedDMG: dmgURL)
        } catch {
            if let updateError = error as? UpdateError {
                status = .error(updateError)
            } else {
                status = .error(.installationFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Cancel

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        status = .idle
    }
}
