import AppKit
import Foundation
import OSLog

nonisolated enum UpdateInstaller {
    /// Full installation pipeline for DMG-based updates.
    /// Mounts DMG, copies .app, replaces current app, restarts.
    static func install(downloadedDMG: URL) async throws {
        let fm = FileManager.default

        // Phase 1: Pre-checks
        Log.updates.info("[UpdateInstaller] phase 1: pre-checks")
        guard fm.fileExists(atPath: downloadedDMG.path) else {
            throw UpdateError.installationFailed("Downloaded file not found")
        }

        // Phase 2: Mount DMG
        Log.updates.info("[UpdateInstaller] phase 2: mounting DMG")
        let mountPoint = try mountDMG(downloadedDMG)
        defer { unmountDMG(mountPoint) }

        // Phase 3: Find .app in mounted volume
        Log.updates.info("[UpdateInstaller] phase 3: finding app bundle")
        guard let sourceApp = try findAppBundle(in: mountPoint) else {
            throw UpdateError.extractionFailed("No .app bundle found in DMG")
        }
        Log.updates.info("[UpdateInstaller] found app: \(sourceApp.lastPathComponent, privacy: .public)")

        // Phase 4: Verify app bundle
        Log.updates.info("[UpdateInstaller] phase 4: verifying app bundle")
        try verifyAppBundle(sourceApp)

        // Phase 5: Copy to temp and strip quarantine
        Log.updates.info("[UpdateInstaller] phase 5: copying to temp")
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EdgeMark")
        let tempDir = cacheDir.appendingPathComponent("EdgeMarkInstall-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempApp = tempDir.appendingPathComponent(sourceApp.lastPathComponent)
        try fm.copyItem(at: sourceApp, to: tempApp)

        // Strip quarantine
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-cr", tempApp.path]
        try xattr.run()
        xattr.waitUntilExit()

        // Phase 6: Replace current app
        Log.updates.info("[UpdateInstaller] phase 6: replacing current app")
        let currentAppURL = Bundle.main.bundleURL
        try replaceApp(current: currentAppURL, replacement: tempApp)
        Log.updates.info("[UpdateInstaller] replacement succeeded")

        // Phase 7: Post-install verify
        Log.updates.info("[UpdateInstaller] phase 7: post-install verification")
        try verifyAppBundle(currentAppURL)

        // Phase 8: Cleanup
        Log.updates.info("[UpdateInstaller] phase 8: cleanup")
        try? fm.removeItem(at: tempDir)
        try? fm.removeItem(at: downloadedDMG)
        let parent = downloadedDMG.deletingLastPathComponent()
        try? fm.removeItem(at: parent)

        // Phase 9: Restart
        Log.updates.info("[UpdateInstaller] phase 9: restarting")
        await restart(appURL: currentAppURL)
    }

    // MARK: - DMG Handling

    /// Mounts a DMG and returns the mount point URL.
    private static func mountDMG(_ dmgURL: URL) throws -> URL {
        // Strip quarantine before mounting
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-d", "com.apple.quarantine", dmgURL.path]
        try? xattr.run()
        xattr.waitUntilExit()

        let hdiutil = Process()
        hdiutil.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        hdiutil.arguments = ["attach", dmgURL.path, "-nobrowse", "-noverify", "-plist"]
        let pipe = Pipe()
        hdiutil.standardOutput = pipe
        let errorPipe = Pipe()
        hdiutil.standardError = errorPipe
        try hdiutil.run()
        hdiutil.waitUntilExit()

        guard hdiutil.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stdoutData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stdoutMsg = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = errorMsg.isEmpty ? stdoutMsg : errorMsg
            Log.updates.error("[UpdateInstaller] hdiutil failed (exit \(hdiutil.terminationStatus)): \(detail, privacy: .public)")
            throw UpdateError.extractionFailed("hdiutil attach failed (exit \(hdiutil.terminationStatus)): \(detail)")
        }

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: outputData, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]]
        else {
            let raw = String(data: outputData.prefix(500), encoding: .utf8) ?? "<binary>"
            Log.updates.error("[UpdateInstaller] failed to parse hdiutil plist: \(raw, privacy: .public)")
            throw UpdateError.extractionFailed("Failed to parse hdiutil output")
        }

        // Find the mount point from the plist output
        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String {
                return URL(fileURLWithPath: mountPoint)
            }
        }

        throw UpdateError.extractionFailed("No mount point found in hdiutil output")
    }

    /// Unmounts a DMG volume.
    private static func unmountDMG(_ mountPoint: URL) {
        let hdiutil = Process()
        hdiutil.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        hdiutil.arguments = ["detach", mountPoint.path, "-quiet"]
        try? hdiutil.run()
        hdiutil.waitUntilExit()
    }

    // MARK: - Helpers

    private static func findAppBundle(in directory: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
        )
        return contents.first { $0.pathExtension == "app" }
    }

    private static func verifyAppBundle(_ appURL: URL) throws {
        // Check bundle identifier matches — integrity is verified via SHA256 checksum
        // before installation, so no codesign check needed (CI builds are unsigned).
        guard let extractedBundle = Bundle(url: appURL),
              let extractedID = extractedBundle.bundleIdentifier,
              let currentID = Bundle.main.bundleIdentifier,
              extractedID == currentID
        else {
            throw UpdateError.installationFailed("Bundle identifier mismatch")
        }
    }

    private static func replaceApp(current: URL, replacement: URL) throws {
        let fm = FileManager.default
        let backupURL = current.appendingPathExtension("bak")

        // Rename current → backup
        if fm.fileExists(atPath: backupURL.path) {
            try fm.removeItem(at: backupURL)
        }
        try fm.moveItem(at: current, to: backupURL)

        do {
            // Move replacement → current location
            try fm.moveItem(at: replacement, to: current)
        } catch {
            // Restore from backup
            Log.updates.error("[UpdateInstaller] move failed, restoring backup")
            try? fm.moveItem(at: backupURL, to: current)
            throw error
        }

        // Remove backup
        try? fm.removeItem(at: backupURL)
    }

    @MainActor
    private static func restart(appURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier

        // Write a standalone script that outlives the parent process
        let scriptPath = "/tmp/edgemark-restart.sh"
        let script = """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done
        sleep 0.5
        open "\(appURL.path)"
        rm -f "\(scriptPath)"
        """
        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        // Launch fully detached — disconnect all I/O so the process survives app exit
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [scriptPath]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.qualityOfService = .utility
        try? task.run()

        // Force exit — terminate(nil) can be blocked by delegates
        exit(0)
    }
}
