import Foundation

enum VideoRemuxer {

    enum RemuxError: LocalizedError {
        case ffmpegNotFound
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "ffmpeg not found. Install it with: brew install ffmpeg"
            case .exportFailed(let msg):
                return "Video remux failed: \(msg)"
            }
        }
    }

    /// Check if file is a proper MP4/MOV container (starts with an "ftyp" box).
    /// MPEG-TS files (common yt-dlp output) start with 0x47 and won't pass this check.
    static func isPlayableContainer(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        let header = handle.readData(ofLength: 12)
        try? handle.close()
        guard header.count >= 8 else { return false }
        // ISO Base Media (MP4/M4V/MOV) files contain "ftyp" at bytes 4-7.
        return header[4] == 0x66  // 'f'
            && header[5] == 0x74  // 't'
            && header[6] == 0x79  // 'y'
            && header[7] == 0x70  // 'p'
    }

    /// Remux a video file into a proper MP4 container using ffmpeg (`-c copy`, no re-encoding).
    /// Replaces the original file in-place.
    @discardableResult
    static func remux(source: URL) async throws -> URL {
        guard let ffmpeg = findFFmpeg() else {
            throw RemuxError.ffmpegNotFound
        }

        let tempURL = source
            .deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".mp4")

        // Run ffmpeg off the cooperative thread pool.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = ffmpeg
                process.arguments = [
                    "-i", source.path,
                    "-c", "copy",
                    "-movflags", "+faststart",
                    "-y",
                    tempURL.path,
                ]
                // Silence ffmpeg banner output.
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    try? FileManager.default.removeItem(at: tempURL)
                    continuation.resume(
                        throwing: RemuxError.exportFailed("ffmpeg exited with code \(process.terminationStatus)")
                    )
                    return
                }

                continuation.resume()
            }
        }

        // Replace original with remuxed file.
        try FileManager.default.removeItem(at: source)
        try FileManager.default.moveItem(at: tempURL, to: source)
        return source
    }

    /// Check whether the file at `url` needs remuxing and, if so, remux it.
    /// Returns `true` when remuxing was actually performed.
    @discardableResult
    static func remuxIfNeeded(at url: URL) async throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard !isPlayableContainer(at: url) else { return false }
        try await remux(source: url)
        return true
    }

    // MARK: - ffmpeg discovery

    /// Search well-known paths for a working ffmpeg binary.
    private static func findFFmpeg() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/opt/homebrew/Cellar/ffmpeg-full/8.0.1_3/bin/ffmpeg",
        ]

        // Also glob Homebrew Cellar for any ffmpeg version.
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
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }

            // Quick smoke-test: can the binary even launch?
            let probe = Process()
            probe.executableURL = url
            probe.arguments = ["-version"]
            probe.standardOutput = FileHandle.nullDevice
            probe.standardError = FileHandle.nullDevice
            do {
                try probe.run()
                probe.waitUntilExit()
                if probe.terminationStatus == 0 {
                    return url
                }
            } catch {
                continue
            }
        }

        return nil
    }
}
