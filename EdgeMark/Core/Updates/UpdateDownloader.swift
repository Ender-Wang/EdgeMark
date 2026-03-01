import Foundation
import OSLog

/// Downloads a release asset with progress tracking via `AsyncStream`.
final nonisolated class UpdateDownloader: NSObject, Sendable, URLSessionDownloadDelegate {
    private let progressContinuation: AsyncStream<UpdateProgress>.Continuation
    let progressStream: AsyncStream<UpdateProgress>

    private let completionContinuation: CheckedContinuation<URL, any Error>
    private let targetDirectory: URL

    /// Speed tracking — accessed only from delegate callbacks (serial URLSession queue)
    private nonisolated(unsafe) var recentBytes: [(date: Date, bytes: Int64)] = []

    init(targetDirectory: URL, completion: CheckedContinuation<URL, any Error>) {
        var cont: AsyncStream<UpdateProgress>.Continuation!
        progressStream = AsyncStream { cont = $0 }
        progressContinuation = cont
        completionContinuation = completion
        self.targetDirectory = targetDirectory
        super.init()
    }

    /// Downloads a release asset DMG file with progress reporting via callback.
    static func download(
        asset: GitHubRelease.Asset,
        onProgress: @escaping @Sendable (UpdateProgress) -> Void,
    ) async throws -> URL {
        guard let downloadURL = URL(string: asset.browserDownloadURL) else {
            throw UpdateError.networkError("Invalid download URL")
        }

        let requiredSpace = Int64(asset.size) * 3
        let tempDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EdgeMark")
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: tempDir.path),
           let freeSpace = attrs[.systemFreeSize] as? Int64,
           freeSpace < requiredSpace
        {
            throw UpdateError.insufficientDiskSpace
        }

        let targetDir = tempDir.appendingPathComponent("EdgeMarkUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        Log.updates.info("[UpdateDownloader] starting download: \(asset.name, privacy: .public) (\(asset.size) bytes)")

        return try await withCheckedThrowingContinuation { continuation in
            let downloader = UpdateDownloader(targetDirectory: targetDir, completion: continuation)

            let config = URLSessionConfiguration.default
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            config.httpAdditionalHeaders = ["User-Agent": "EdgeMark/\(version) (macOS)"]
            let session = URLSession(configuration: config, delegate: downloader, delegateQueue: nil)

            Task {
                for await progress in downloader.progressStream {
                    onProgress(progress)
                }
            }

            let task = session.downloadTask(with: downloadURL)
            task.resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64,
    ) {
        let now = Date()
        recentBytes.append((date: now, bytes: totalBytesWritten))

        // Keep only last 3 seconds for rolling average
        let cutoff = now.addingTimeInterval(-3)
        recentBytes.removeAll { $0.date < cutoff }

        let speed: Double
        if let oldest = recentBytes.first, recentBytes.count > 1 {
            let elapsed = now.timeIntervalSince(oldest.date)
            let bytesInWindow = totalBytesWritten - oldest.bytes
            speed = elapsed > 0 ? Double(bytesInWindow) / elapsed : 0
        } else {
            speed = 0
        }

        let progress = UpdateProgress(
            bytesDownloaded: totalBytesWritten,
            totalBytes: totalBytesExpectedToWrite,
            speedBytesPerSecond: speed,
        )
        progressContinuation.yield(progress)
    }

    nonisolated func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL,
    ) {
        let destination = targetDirectory.appendingPathComponent("EdgeMark-update.dmg")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            Log.updates.info("[UpdateDownloader] download complete: \(destination.path, privacy: .public)")
            progressContinuation.finish()
            completionContinuation.resume(returning: destination)
        } catch {
            progressContinuation.finish()
            completionContinuation.resume(throwing: UpdateError.networkError(error.localizedDescription))
        }
    }

    nonisolated func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didCompleteWithError error: (any Error)?,
    ) {
        if let error {
            progressContinuation.finish()
            if (error as NSError).code == NSURLErrorCancelled {
                completionContinuation.resume(throwing: UpdateError.cancelled)
            } else {
                completionContinuation.resume(throwing: UpdateError.networkError(error.localizedDescription))
            }
        }
    }
}
