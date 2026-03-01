import CryptoKit
import Foundation

nonisolated enum ChecksumVerifier {
    /// Compute SHA256 of a file at the given URL.
    static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { handle.closeFile() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1 MB chunks
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: bufferSize)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Verify a file's SHA256 against an expected checksum string.
    static func verify(_ fileURL: URL, expected: String) throws -> Bool {
        let actual = try sha256(of: fileURL)
        return actual.lowercased() == expected.lowercased()
    }
}
