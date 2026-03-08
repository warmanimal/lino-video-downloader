import Foundation

enum Constants {
    static var storageDir: URL {
        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        return moviesDir.appendingPathComponent("Lino")
    }

    static var thumbnailDir: URL {
        storageDir.appendingPathComponent(".thumbnails")
    }

    static var appSupportDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Lino")
    }

    static var databasePath: URL {
        appSupportDir.appendingPathComponent("lino.sqlite")
    }

    static var ytdlpBinDir: URL {
        appSupportDir.appendingPathComponent("bin")
    }

    /// The managed copy in app support (used when we have a standalone binary)
    static var ytdlpManagedPath: URL {
        ytdlpBinDir.appendingPathComponent("yt-dlp")
    }

    /// Resolves the best available yt-dlp path.
    /// Prefers our managed standalone binary, falls back to system Homebrew.
    static var ytdlpPath: URL {
        let managed = ytdlpManagedPath
        let fm = FileManager.default

        // Use managed binary if it exists and is a real binary (not a tiny shim)
        if fm.isExecutableFile(atPath: managed.path) {
            if let attrs = try? fm.attributesOfItem(atPath: managed.path),
               let size = attrs[.size] as? Int64, size > 1000 {
                return managed
            }
        }

        // Fall back to system paths
        let systemPaths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
        ]
        for path in systemPaths {
            if fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // Return managed path as default (will fail with "not found" downstream)
        return managed
    }

    /// Environment dict for subprocesses — ensures Homebrew tools (ffmpeg, deno) are findable.
    static var subprocessEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        let missing = extraPaths.filter { !currentPath.contains($0) }
        if !missing.isEmpty {
            env["PATH"] = (missing + [currentPath]).joined(separator: ":")
        }
        return env
    }

    /// Resolves a working ffmpeg binary.
    /// The default Homebrew `ffmpeg` may have broken dylib links, so we probe
    /// Cellar versioned paths (including `ffmpeg-full`) and smoke-test each candidate.
    static var ffmpegPath: URL? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
        ]

        let cellarRoots = [
            "/opt/homebrew/Cellar/ffmpeg",
            "/opt/homebrew/Cellar/ffmpeg-full",
            "/usr/local/Cellar/ffmpeg",
            "/usr/local/Cellar/ffmpeg-full",
        ]

        var allCandidates = candidates
        for root in cellarRoots {
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: root) {
                for version in versions {
                    allCandidates.append("\(root)/\(version)/bin/ffmpeg")
                }
            }
        }

        for path in allCandidates {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            let probe = Process()
            probe.executableURL = URL(fileURLWithPath: path)
            probe.arguments = ["-version"]
            probe.standardOutput = FileHandle.nullDevice
            probe.standardError = FileHandle.nullDevice
            do {
                try probe.run()
                probe.waitUntilExit()
                if probe.terminationStatus == 0 {
                    return URL(fileURLWithPath: path)
                }
            } catch {
                continue
            }
        }
        return nil
    }

    static let maxConcurrentDownloads = 2

    static func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        for dir in [storageDir, thumbnailDir, appSupportDir, ytdlpBinDir] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
}
