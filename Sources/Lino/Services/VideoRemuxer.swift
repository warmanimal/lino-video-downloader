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

    /// Codecs that AVPlayer on macOS can decode natively.
    private static let playableVideoCodecs: Set<String> = ["h264", "hevc", "h265", "mpeg4", "prores"]

    // MARK: - Checks

    /// Check if file is a proper MP4/MOV container (starts with an "ftyp" box).
    static func isPlayableContainer(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        let header = handle.readData(ofLength: 12)
        try? handle.close()
        guard header.count >= 8 else { return false }
        return header[4] == 0x66 && header[5] == 0x74
            && header[6] == 0x79 && header[7] == 0x70
    }

    /// Probe the video codec using ffprobe. Returns e.g. "h264", "vp9", "av1".
    static func videoCodec(at url: URL) -> String? {
        guard let ffmpeg = Constants.ffmpegPath else { return nil }
        let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        guard FileManager.default.isExecutableFile(atPath: ffprobe.path) else { return nil }

        let process = Process()
        process.executableURL = ffprobe
        process.arguments = [
            "-v", "quiet",
            "-select_streams", "v:0",
            "-show_entries", "stream=codec_name",
            "-of", "csv=p=0",
            url.path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Returns `true` when the file is in a playable container AND uses a codec AVPlayer supports.
    static func isPlayable(at url: URL) -> Bool {
        guard isPlayableContainer(at: url) else { return false }
        guard let codec = videoCodec(at: url) else {
            // If we can't probe, optimistically assume it's playable.
            return true
        }
        return playableVideoCodecs.contains(codec)
    }

    // MARK: - Remux (container change only, no re-encoding)

    /// Remux a video file into a proper MP4 container using ffmpeg (`-c copy`).
    @discardableResult
    static func remux(source: URL) async throws -> URL {
        try await runFFmpeg(args: [
            "-i", source.path,
            "-c", "copy",
            "-movflags", "+faststart",
        ], output: source)
    }

    // MARK: - Transcode (re-encode video to H.264)

    /// Transcode a video to H.264 using VideoToolbox hardware acceleration.
    @discardableResult
    static func transcodeToH264(source: URL) async throws -> URL {
        try await runFFmpeg(args: [
            "-i", source.path,
            "-c:v", "h264_videotoolbox",
            "-q:v", "65",
            "-c:a", "copy",
            "-movflags", "+faststart",
        ], output: source)
    }

    // MARK: - Combined check & fix

    /// Ensure the file at `url` is playable by AVPlayer: proper MP4 container with a supported codec.
    /// Remuxes or transcodes as needed. Returns `true` when any conversion was performed.
    @discardableResult
    static func ensurePlayable(at url: URL) async throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        if !isPlayableContainer(at: url) {
            // Wrong container (e.g. MPEG-TS) — remux first, then check codec.
            try await remux(source: url)
        }

        if let codec = videoCodec(at: url), !playableVideoCodecs.contains(codec) {
            // Unsupported codec (e.g. VP9, AV1) — transcode to H.264.
            try await transcodeToH264(source: url)
            return true
        }

        return true
    }

    // MARK: - Private

    /// Run ffmpeg with the given arguments, writing to a temp file then replacing the source.
    private static func runFFmpeg(args: [String], output source: URL) async throws -> URL {
        guard let ffmpeg = Constants.ffmpegPath else {
            throw RemuxError.ffmpegNotFound
        }

        let tempURL = source
            .deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".mp4")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = ffmpeg
                process.arguments = args + ["-y", tempURL.path]
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

        try FileManager.default.removeItem(at: source)
        try FileManager.default.moveItem(at: tempURL, to: source)
        return source
    }
}
