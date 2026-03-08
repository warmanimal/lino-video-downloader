import Foundation

@Observable
@MainActor
final class YtDlpUpdateService {
    private(set) var currentVersion: String?
    private(set) var isUpdating = false
    private(set) var lastError: String?

    private let releasesURL = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!

    init() {
        // Don't run subprocesses during init — defer to ensureAvailable()
    }

    /// Ensures yt-dlp is available.
    /// Tries: managed standalone binary → bundled in app → system Homebrew (used in-place).
    /// Must be called from a Task, not synchronously during init.
    func ensureAvailable() async {
        let fm = FileManager.default

        do {
            try Constants.ensureDirectoriesExist()
        } catch {
            lastError = "Failed to create directories: \(error.localizedDescription)"
            return
        }

        let managedPath = Constants.ytdlpManagedPath

        // Check if we already have a standalone binary in app support
        if fm.isExecutableFile(atPath: managedPath.path) {
            if let attrs = try? fm.attributesOfItem(atPath: managedPath.path),
               let size = attrs[.size] as? Int64, size > 1000 {
                currentVersion = await Self.fetchInstalledVersion()
                return
            }
            // It's a shim/too small — remove it
            try? fm.removeItem(at: managedPath)
        }

        // Try copying standalone binary from app bundle
        if let bundledPath = Bundle.main.url(forResource: "yt-dlp", withExtension: nil) {
            do {
                let attrs = try fm.attributesOfItem(atPath: bundledPath.path)
                if let size = attrs[.size] as? Int64, size > 1000 {
                    try fm.copyItem(at: bundledPath, to: managedPath)
                    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: managedPath.path)
                    currentVersion = await Self.fetchInstalledVersion()
                    return
                }
            } catch {
                // Fall through to system path check
            }
        }

        // Constants.ytdlpPath dynamically falls back to system Homebrew.
        // Just check if it resolves to something usable.
        let resolved = Constants.ytdlpPath
        if fm.isExecutableFile(atPath: resolved.path) {
            currentVersion = await Self.fetchInstalledVersion()
            lastError = nil
            return
        }

        lastError = "yt-dlp not found. Install via Settings or run: brew install yt-dlp"
    }

    /// Checks GitHub releases for a newer version and updates if available.
    func checkForUpdate() async {
        isUpdating = true
        lastError = nil
        defer { isUpdating = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: releasesURL)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            guard release.tagName != currentVersion else {
                return // Already up to date
            }

            // Find the macOS binary asset
            guard let asset = release.assets.first(where: { $0.name == "yt-dlp_macos" }) else {
                lastError = "No macOS binary found in release \(release.tagName)"
                return
            }

            guard let downloadURL = URL(string: asset.browserDownloadUrl) else {
                lastError = "Invalid download URL"
                return
            }

            // Download the new binary
            let (binaryData, response) = try await URLSession.shared.data(from: downloadURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                lastError = "Failed to download update"
                return
            }

            // Replace managed standalone binary
            let targetPath = Constants.ytdlpManagedPath
            let fm = FileManager.default

            if fm.fileExists(atPath: targetPath.path) {
                try fm.removeItem(at: targetPath)
            }

            try binaryData.write(to: targetPath)
            try fm.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: targetPath.path
            )

            currentVersion = release.tagName
        } catch {
            lastError = "Update failed: \(error.localizedDescription)"
        }
    }

    /// Allows user to manually select a yt-dlp binary.
    func installFromFile(_ url: URL) async throws {
        let fm = FileManager.default
        let targetPath = Constants.ytdlpManagedPath

        try Constants.ensureDirectoriesExist()

        if fm.fileExists(atPath: targetPath.path) {
            try fm.removeItem(at: targetPath)
        }

        try fm.copyItem(at: url, to: targetPath)
        try fm.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: targetPath.path
        )

        currentVersion = await Self.fetchInstalledVersion()
        lastError = nil
    }

    /// Runs yt-dlp --version on a background thread to avoid blocking the main thread.
    private static func fetchInstalledVersion() async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let ytdlpPath = Constants.ytdlpPath

                guard FileManager.default.isExecutableFile(atPath: ytdlpPath.path) else {
                    continuation.resume(returning: nil)
                    return
                }

                let process = Process()
                process.executableURL = ytdlpPath
                process.environment = Constants.subprocessEnvironment
                process.arguments = ["--version"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let version = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: version)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private struct GitHubRelease: Codable {
    let tagName: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}
