import Foundation
import OSLog

actor UpdateChecker {
    private let repoOwner = "Ender-Wang"
    private let repoName = "EdgeMark"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        config.httpAdditionalHeaders = [
            "User-Agent": "EdgeMark/\(version) (macOS)",
            "Accept": "application/vnd.github+json",
        ]
        session = URLSession(configuration: config)
    }

    /// Fetches the latest release from GitHub.
    /// - Parameter includeBeta: If true, also considers prerelease (beta/develop) versions.
    /// - Returns: The newest release if it's newer than the current version, nil if up-to-date.
    func checkForUpdate(includeBeta: Bool = false) async throws -> GitHubRelease? {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        if includeBeta {
            return try await checkAllReleases(currentVersion: currentVersion)
        } else {
            return try await checkLatestStable(currentVersion: currentVersion)
        }
    }

    /// Check only the latest stable release.
    private func checkLatestStable(currentVersion: String) async throws -> GitHubRelease? {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        Log.updates.info("[UpdateChecker] checking for stable updates...")

        let release = try await fetchRelease(from: url)

        let isNewer = release.version.compare(currentVersion, options: .numeric) == .orderedDescending
        if isNewer {
            Log.updates.info("[UpdateChecker] stable update available: v\(release.version, privacy: .public) (current: v\(currentVersion, privacy: .public))")
            return release
        }

        Log.updates.info("[UpdateChecker] up to date (v\(currentVersion, privacy: .public))")
        return nil
    }

    /// Check all releases including prereleases, return the newest one.
    private func checkAllReleases(currentVersion: String) async throws -> GitHubRelease? {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases?per_page=10")!
        Log.updates.info("[UpdateChecker] checking for updates (including beta)...")

        let (data, response) = try await session.data(from: url)
        try validateResponse(response)

        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)

        let newest = releases.first { release in
            release.version.compare(currentVersion, options: .numeric) == .orderedDescending
        }

        if let newest {
            let channel = newest.prerelease ? "beta" : "stable"
            Log.updates.info("[UpdateChecker] \(channel, privacy: .public) update available: v\(newest.version, privacy: .public) (current: v\(currentVersion, privacy: .public))")
            return newest
        }

        Log.updates.info("[UpdateChecker] up to date (v\(currentVersion, privacy: .public))")
        return nil
    }

    /// Fetch and decode a single release from a URL.
    private func fetchRelease(from url: URL) async throws -> GitHubRelease {
        let (data, response) = try await session.data(from: url)
        try validateResponse(response)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// Validate HTTP response status.
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 403, 429:
            Log.updates.error("[UpdateChecker] rate limited (HTTP \(httpResponse.statusCode))")
            throw UpdateError.rateLimited
        default:
            Log.updates.error("[UpdateChecker] unexpected HTTP \(httpResponse.statusCode)")
            throw UpdateError.invalidResponse
        }
    }

    /// Fetches the release date for a specific version tag (e.g., "0.24" → looks up "v0.24").
    func fetchReleaseDate(forVersion version: String) async -> Date? {
        let tag = version.hasPrefix("v") ? version : "v\(version)"
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/tags/\(tag)")!
        guard let release = try? await fetchRelease(from: url) else { return nil }
        return release.publishedDate
    }

    /// Downloads the checksum string from a `.sha256` asset URL.
    func fetchChecksum(from asset: GitHubRelease.Asset) async throws -> String {
        let url = URL(string: asset.browserDownloadURL)!
        let (data, _) = try await session.data(from: url)
        let content = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Handle formats like "abc123  filename.dmg" or just "abc123"
        return content.components(separatedBy: .whitespaces).first ?? content
    }
}
