import Foundation

// MARK: - GitHub Release

nonisolated struct GitHubRelease: Codable, Sendable {
    let tagName: String
    let name: String
    let body: String
    let htmlURL: String
    let publishedAt: String
    let assets: [Asset]

    struct Asset: Codable, Sendable {
        let name: String
        let browserDownloadURL: String
        let size: Int

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
        case prerelease
    }

    /// The version string without the "v" prefix (e.g., "0.25").
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    /// The first `.dmg` asset, if any.
    var dmgAsset: Asset? {
        assets.first { $0.name.hasSuffix(".dmg") }
    }

    /// The `.sha256` checksum asset, if any.
    var checksumAsset: Asset? {
        assets.first { $0.name.hasSuffix(".sha256") }
    }

    /// Whether this is a prerelease (beta/develop channel).
    let prerelease: Bool

    /// Published date parsed from ISO 8601.
    var publishedDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: publishedAt) ?? ISO8601DateFormatter().date(from: publishedAt)
    }
}

// MARK: - Update Status

nonisolated enum UpdateStatus: Sendable {
    case idle
    case checking
    case available(GitHubRelease)
    case downloading(UpdateProgress)
    case readyToInstall(GitHubRelease, URL)
    case installing
    case upToDate
    case error(UpdateError)
}

// MARK: - Update Progress

nonisolated struct UpdateProgress: Sendable {
    let bytesDownloaded: Int64
    let totalBytes: Int64
    let speedBytesPerSecond: Double

    var percentage: Double {
        Double(bytesDownloaded) / Double(max(totalBytes, 1))
    }

    var etaSeconds: Double {
        Double(totalBytes - bytesDownloaded) / max(speedBytesPerSecond, 1)
    }
}

// MARK: - Update Error

nonisolated enum UpdateError: LocalizedError, Sendable {
    case networkError(String)
    case invalidResponse
    case rateLimited
    case noAssetFound
    case checksumMismatch
    case extractionFailed(String)
    case installationFailed(String)
    case insufficientDiskSpace
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .networkError(msg): "Network error: \(msg)"
        case .invalidResponse: "Invalid response from GitHub API"
        case .rateLimited: "GitHub API rate limit exceeded. Try again later."
        case .noAssetFound: "No downloadable asset found in this release"
        case .checksumMismatch: "Download integrity check failed (SHA256 mismatch)"
        case let .extractionFailed(msg): "Failed to extract update: \(msg)"
        case let .installationFailed(msg): "Installation failed: \(msg)"
        case .insufficientDiskSpace: "Not enough disk space to download and install the update"
        case .cancelled: "Update cancelled"
        }
    }
}
